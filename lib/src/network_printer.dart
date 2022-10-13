/*
 * esc_pos_printer
 * Created by Andrey Ushakov
 * 
 * Copyright (c) 2019-2020. All rights reserved.
 * See LICENSE for distribution and usage details.
 */

import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data' show Uint8List;
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:image/image.dart';
import 'package:tcp_client_dart/tcp_client_dart.dart';
import './enums.dart';
import 'package:esc_pos_utils/src/commands.dart' as commands;

/// Network Printer
class NetworkPrinter {
  NetworkPrinter(this._paperSize, this._profile, this._globalCodeTable, {int spaceBetweenRows = 5}) {
    _generator = Generator(paperSize, profile, spaceBetweenRows: spaceBetweenRows);
  }

  final PaperSize _paperSize;
  final CapabilityProfile _profile;
  final String _globalCodeTable;
  String? _host;
  int? _port;
  late Generator _generator;
  Socket? _client;
  //late TcpClient _client;
  late List<List<int>> _dataStream;

  int? get port => _port;
  String? get host => _host;
  PaperSize get paperSize => _paperSize;
  CapabilityProfile get profile => _profile;
  //late StreamSubscription<Uint8List> _socketListenerSubscription;
  int attempt = 0;
  bool _stopTrying = true;

  Future<bool> connect(String host, Function(Object err, StackTrace) onError, {int port = 91000, Duration timeout = const Duration(seconds: 5), int maxRetry = 3}) async {
    _host = host;
    _port = port;
    _dataStream = [];

    log('CONNECTING attempt:$attempt/$maxRetry');
    if (attempt == 0) _stopTrying = false;
    if (attempt == maxRetry) {
      return false;
    }
    if (_stopTrying) {
      return false;
    }

    attempt++;

    try {
      _client?.close();
      await runZonedGuarded(() async {
        _client = await Socket.connect(host, port, timeout: timeout).catchError(onError);
      }, onError);
      if (_client == null) {
        return await connect(host, onError, port: port, timeout: timeout, maxRetry: maxRetry);
      }

      _enableKeepalive(_client!, keepaliveInterval: timeout.inSeconds, keepaliveSuccessiveInterval: timeout.inSeconds, keepaliveEnabled: true);
      await runZonedGuarded(() async {
        _client!.handleError((Object err, StackTrace stackTrace) {
          print([err, stackTrace]);
          onError(err, stackTrace);
          Timer(timeout, () async {
            attempt = 1;
            await connect(host, onError, port: port, timeout: timeout, maxRetry: maxRetry);
          });
        });
      }, onError);
    } catch (e) {
      print(e);
      return false;
    }
    return true;

/*
      _client = await Socket.connect(host, port, timeout: timeout);
      _enableKeepalive(_client, keepaliveInterval: timeout.inSeconds, keepaliveSuccessiveInterval: timeout.inSeconds, keepaliveEnabled: true);
      print([_client.port, _client.address, _client.remotePort, _client.remotePort]);
      _client.handleError(onError);
      _socketListenerSubscription = _client.listen(null, onError: onError);

      reset();
      await send();
      return Future<PosPrintResult>.value(PosPrintResult.success);
    } catch (e) {
      if (e is SocketException) {
        log(e.message);
      }
      rethrow;
    }
    */
  }

  /// [delayMs]: milliseconds to wait after destroying the socket
  void disconnect({int? delayMs}) async {
    destroy();
    if (delayMs != null) {
      await Future.delayed(Duration(milliseconds: delayMs), () => null);
    }
  }

  void _add(List<int> data) async {
    _dataStream.add(data);
  }

  void send() {
    // ignore: prefer_foreach
    for (var data in _dataStream) {
      _client!.add(data);
      //_client.send(data);
    }
    _flush();
  }

  void _flush() {
    _dataStream.clear();
  }

  void destroy() {
    //_client.destroy();
    _client!.close();
    //_socketListenerSubscription.cancel();
  }

  void _enableKeepalive(Socket socket, {bool keepaliveEnabled = true, int keepaliveInterval = 60, int keepaliveSuccessiveInterval = 10}) {
    // Enable keepalive probes every 60 seconds with 3 retries each 10 seconds
    const keepaliveSuccessiveCount = 3;

    if (Platform.isIOS || Platform.isMacOS) {
      final enableKeepaliveOption = RawSocketOption.fromBool(
          0xffff, // SOL_SOCKET
          0x0008, // SO_KEEPALIVE
          keepaliveEnabled);
      final keepaliveIntervalOption = RawSocketOption.fromInt(
          6, // IPPROTO_TCP
          0x10, // TCP_KEEPALIVE
          keepaliveInterval);
      final keepaliveSuccessiveIntervalOption = RawSocketOption.fromInt(
        6, // IPPROTO_TCP
        0x101, // TCP_KEEPINTVL
        keepaliveSuccessiveInterval,
      );
      final keepaliveusccessiveCountOption = RawSocketOption.fromInt(
          6, // IPPROTO_TCP
          0x102, // TCP_KEEPCNT
          keepaliveSuccessiveCount);

      socket.setRawOption(enableKeepaliveOption);
      socket.setRawOption(keepaliveIntervalOption);
      socket.setRawOption(keepaliveSuccessiveIntervalOption);
      socket.setRawOption(keepaliveusccessiveCountOption);
    } else if (Platform.isAndroid) {
      final enableKeepaliveOption = RawSocketOption.fromBool(
          0x1, // SOL_SOCKET
          0x0009, // SO_KEEPALIVE
          keepaliveEnabled);
      final keepaliveIntervalOption = RawSocketOption.fromInt(
          6, // IPPROTO_TCP
          4, // TCP_KEEPIDLE
          keepaliveInterval);
      final keepaliveSuccessiveIntervalOption = RawSocketOption.fromInt(
        6, // IPPROTO_TCP
        5, // TCP_KEEPINTVL
        keepaliveSuccessiveInterval,
      );
      final keepaliveusccessiveCountOption = RawSocketOption.fromInt(
          6, // IPPROTO_TCP
          6, // TCP_KEEPCNT
          keepaliveSuccessiveCount);

      socket.setRawOption(enableKeepaliveOption);
      socket.setRawOption(keepaliveIntervalOption);
      socket.setRawOption(keepaliveSuccessiveIntervalOption);
      socket.setRawOption(keepaliveusccessiveCountOption);
    }
  }

  // ************************ Printer Commands ************************
  void reset() {
    _add(_generator.reset());
  }

  void text(
    String text, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    bool containsChinese = false,
    int? maxCharsPerLine,
  }) {
    _add(_generator.text(text, styles: styles, linesAfter: linesAfter, containsChinese: containsChinese, maxCharsPerLine: maxCharsPerLine));
  }

  void setGlobalCodeTable(String codeTable) {
    _add(_generator.setGlobalCodeTable(codeTable));
  }

  void setGlobalFont(PosFontType font, {int? maxCharsPerLine}) {
    _add(_generator.setGlobalFont(font, maxCharsPerLine: maxCharsPerLine));
  }

  void setStyles(PosStyles styles, {bool isKanji = false}) {
    _add(_generator.setStyles(styles, isKanji: isKanji));
  }

  void rawBytes(List<int> cmd, {bool isKanji = false}) {
    _add(_generator.rawBytes(cmd, isKanji: isKanji));
  }

  void emptyLines(int n) {
    _add(_generator.emptyLines(n));
  }

  void feed(int n) {
    _add(_generator.feed(n));
  }

  void cut({PosCutMode mode = PosCutMode.full}) {
    _add(_generator.cut(mode: mode));
  }

  void printCodeTable({String? codeTable}) {
    _add(_generator.printCodeTable(codeTable: codeTable));
  }

  void printCurrencySymbol({String? codeTable}) {
    List<int> list = List.from(commands.cCodeTable.codeUnits);
    List<int> endList = [];
    int count = 0;
    list.forEach((e) {
      endList.addAll((count++).toString().codeUnits);
      endList.add(e);
    });
    final Uint8List encoded = Uint8List.fromList(list..add(_profile.getCodePageId(codeTable)));
    const PosTextSize size = PosTextSize.size1;
    textEncoded(
      encoded,
      styles: PosStyles(width: size, height: size, codeTable: codeTable),
    );

    // Back to initial code table
    setGlobalCodeTable(_globalCodeTable);
  }

  void beep({int n = 3, PosBeepDuration duration = PosBeepDuration.beep450ms}) {
    _add(_generator.beep(n: n, duration: duration));
  }

  void reverseFeed(int n) {
    _add(_generator.reverseFeed(n));
  }

  void row(List<PosColumn> cols) {
    _add(_generator.row(cols));
  }

  void image(Image imgSrc, {PosAlign align = PosAlign.center}) {
    _add(_generator.image(imgSrc, align: align));
  }

  void imageRaster(
    Image image, {
    PosAlign align = PosAlign.center,
    bool highDensityHorizontal = true,
    bool highDensityVertical = true,
    PosImageFn imageFn = PosImageFn.bitImageRaster,
  }) {
    _add(_generator.imageRaster(
      image,
      align: align,
      highDensityHorizontal: highDensityHorizontal,
      highDensityVertical: highDensityVertical,
      imageFn: imageFn,
    ));
  }

  void barcode(
    Barcode barcode, {
    int? width,
    int? height,
    BarcodeFont? font,
    BarcodeText textPos = BarcodeText.below,
    PosAlign align = PosAlign.center,
  }) {
    _add(_generator.barcode(
      barcode,
      width: width,
      height: height,
      font: font,
      textPos: textPos,
      align: align,
    ));
  }

  void qrcode(
    String text, {
    PosAlign align = PosAlign.center,
    QRSize size = QRSize.Size4,
    QRCorrection cor = QRCorrection.L,
  }) {
    _add(_generator.qrcode(text, align: align, size: size, cor: cor));
  }

  void drawer({PosDrawer pin = PosDrawer.pin2}) {
    _add(_generator.drawer(pin: pin));
  }

  void hr({String ch = '-', int? len, int linesAfter = 0}) {
    _add(_generator.hr(ch: ch, linesAfter: linesAfter));
  }

  void textEncoded(
    Uint8List textBytes, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    int? maxCharsPerLine,
  }) {
    _add(_generator.textEncoded(
      textBytes,
      styles: styles,
      linesAfter: linesAfter,
      maxCharsPerLine: maxCharsPerLine,
    ));
  }
  // ************************ (end) Printer Commands ************************
}
