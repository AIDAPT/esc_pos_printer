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
import './enums.dart';

/// Network Printer
class NetworkPrinter {
  NetworkPrinter(this._paperSize, this._profile, {int spaceBetweenRows = 5}) {
    _generator = Generator(paperSize, profile, spaceBetweenRows: spaceBetweenRows);
  }

  final PaperSize _paperSize;
  final CapabilityProfile _profile;
  String? _host;
  int? _port;
  late Generator _generator;
  late RawSocket _client;

  int? get port => _port;
  String? get host => _host;
  PaperSize get paperSize => _paperSize;
  CapabilityProfile get profile => _profile;
  late StreamSubscription<RawSocketEvent> _socketListenerSubscription;

  Future<PosPrintResult> connect(String host, {int port = 91000, Duration timeout = const Duration(seconds: 5), Function(RawSocketEvent?)? onData, Function()? onErrorListener, Function()? onDone}) async {
    _host = host;
    _port = port;
    try {
      _client = await RawSocket.connect(host, port, sourcePort: port, timeout: timeout);
      _socketListenerSubscription = _client.listen(onData, onError: onErrorListener, onDone: onDone, cancelOnError: true);

      /*dataStreamController = StreamController();
      dataStream = dataStreamController.stream;
      _socket = await Socket.connect(host, port, timeout: timeout, sourcePort: );
      _socket.handleError((dynamic err) {
        if (onErrorListener != null) {
          onErrorListener(err);
        }
        print(["PRINTER handleError", err.toString()]);
      });

      dataStream.listen((List<int> data) {
        if (onData != null) {
          onData(Uint8List.fromList(data));
        }
        print(["PRINTER onData"]);
      }, onError: (dynamic err) {
        if (onErrorListener != null) {
          onErrorListener(err);
        }
        print(["PRINTER onError", err.toString()]);
      }, onDone: () {
        if (onData != null) {
          onData(null);
        }
        print(["PRINTER onDone"]);
      });

      _socket.addStream(dataStream);*/
      send(_generator.reset());
      return Future<PosPrintResult>.value(PosPrintResult.success);
    } catch (e) {
      if (e is SocketException) {
        log(e.message);
      }
      rethrow;
    }
  }

  /// [delayMs]: milliseconds to wait after destroying the socket
  void disconnect({int? delayMs}) async {
    destroy();
    if (delayMs != null) {
      await Future.delayed(Duration(milliseconds: delayMs), () => null);
    }
  }

  void send(List<int> data) {
    try {
      int writtenData = _client.sendMessage([], data);
      print(['SOCKET WRITTEN DATA:$writtenData/${data.length}']);
    } on OSError catch (err) {
      print(['SOCKET ERROR', err.errorCode, err.message]);
      rethrow;
    }
  }

  void destroy() {
    _client.shutdown(SocketDirection.both);
    _socketListenerSubscription.cancel();
  }

  // ************************ Printer Commands ************************
  void reset() {
    send(_generator.reset());
  }

  void text(
    String text, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    bool containsChinese = false,
    int? maxCharsPerLine,
  }) {
    send(_generator.text(text, styles: styles, linesAfter: linesAfter, containsChinese: containsChinese, maxCharsPerLine: maxCharsPerLine));
  }

  void setGlobalCodeTable(String codeTable) {
    send(_generator.setGlobalCodeTable(codeTable));
  }

  void setGlobalFont(PosFontType font, {int? maxCharsPerLine}) {
    send(_generator.setGlobalFont(font, maxCharsPerLine: maxCharsPerLine));
  }

  void setStyles(PosStyles styles, {bool isKanji = false}) {
    send(_generator.setStyles(styles, isKanji: isKanji));
  }

  void rawBytes(List<int> cmd, {bool isKanji = false}) {
    send(_generator.rawBytes(cmd, isKanji: isKanji));
  }

  void emptyLines(int n) {
    send(_generator.emptyLines(n));
  }

  void feed(int n) {
    send(_generator.feed(n));
  }

  void cut({PosCutMode mode = PosCutMode.full}) {
    send(_generator.cut(mode: mode));
  }

  void printCodeTable({String? codeTable}) {
    send(_generator.printCodeTable(codeTable: codeTable));
  }

  void beep({int n = 3, PosBeepDuration duration = PosBeepDuration.beep450ms}) {
    send(_generator.beep(n: n, duration: duration));
  }

  void reverseFeed(int n) {
    send(_generator.reverseFeed(n));
  }

  void row(List<PosColumn> cols) {
    send(_generator.row(cols));
  }

  void image(Image imgSrc, {PosAlign align = PosAlign.center}) {
    send(_generator.image(imgSrc, align: align));
  }

  void imageRaster(
    Image image, {
    PosAlign align = PosAlign.center,
    bool highDensityHorizontal = true,
    bool highDensityVertical = true,
    PosImageFn imageFn = PosImageFn.bitImageRaster,
  }) {
    send(_generator.imageRaster(
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
    send(_generator.barcode(
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
    send(_generator.qrcode(text, align: align, size: size, cor: cor));
  }

  void drawer({PosDrawer pin = PosDrawer.pin2}) {
    send(_generator.drawer(pin: pin));
  }

  void hr({String ch = '-', int? len, int linesAfter = 0}) {
    send(_generator.hr(ch: ch, linesAfter: linesAfter));
  }

  void textEncoded(
    Uint8List textBytes, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    int? maxCharsPerLine,
  }) {
    send(_generator.textEncoded(
      textBytes,
      styles: styles,
      linesAfter: linesAfter,
      maxCharsPerLine: maxCharsPerLine,
    ));
  }
  // ************************ (end) Printer Commands ************************
}
