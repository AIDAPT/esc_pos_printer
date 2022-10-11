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
  late Socket _socket;

  int? get port => _port;
  String? get host => _host;
  PaperSize get paperSize => _paperSize;
  CapabilityProfile get profile => _profile;
  late Stream<List<int>> dataStream;
  late StreamController<List<int>> dataStreamController;

  Future<PosPrintResult> connect(String host, {int port = 91000, Duration timeout = const Duration(seconds: 5), Function(dynamic)? onErrorListener, Function(Uint8List?)? onData, Function(dynamic)? onClose}) async {
    _host = host;
    _port = port;
    try {
      dataStreamController = StreamController();
      dataStream = dataStreamController.stream;
      _socket = await Socket.connect(host, port, timeout: timeout);
      _socket.addStream(dataStream);
      _socket.handleError((dynamic err) {
        if (onErrorListener != null) {
          onErrorListener(err);
        }
        print(["PRINTER handleError", err.toString()]);
      });

      _socket.done.then((dynamic value) {
        if (onClose != null) {
          onClose(value);
        }
        print(["PRINTER onDone", value.toString()]);
      }).catchError((dynamic err) {
        if (onErrorListener != null) {
          onErrorListener(err);
        }
        print(["PRINTER catchError", err.toString()]);
      });

      _socket.done.onError((err, stackTrace) {
        if (onErrorListener != null) {
          onErrorListener(err);
        }
        print(["PRINTER onError", err.toString(), stackTrace]);
      });

      _socket.listen((data) {
        if (onData != null) {
          onData(data);
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
    _socket.destroy();
    if (delayMs != null) {
      await Future.delayed(Duration(milliseconds: delayMs), () => null);
    }
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

  void send(List<int> data) {
    dataStreamController.add(data);
  }
}
