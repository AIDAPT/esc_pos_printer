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
  late Socket _client;

  int? get port => _port;
  String? get host => _host;
  PaperSize get paperSize => _paperSize;
  CapabilityProfile get profile => _profile;
  late StreamSubscription<Uint8List> _socketListenerSubscription;
  Future<PosPrintResult> connect(String host, {int port = 91000, Duration timeout = const Duration(seconds: 5), Function(Object err, StackTrace)? onError}) async {
    _host = host;
    _port = port;
    try {
      _client = await Socket.connect(host, port, timeout: timeout);
      print([_client.port, _client.address, _client.remotePort, _client.remotePort]);
      _socketListenerSubscription = _client.listen(null, onError: onError);

      reset();
      return Future<PosPrintResult>.value(PosPrintResult.success);
    } catch (e) {
      if (e is SocketException) {
        log(e.message);
      }
      rethrow;
    }
  }

  /// [delayMs]: milliseconds to wait after destroying the socket
  Future disconnect({int? delayMs}) async {
    if (delayMs != null) {
      await Future.delayed(Duration(milliseconds: delayMs), () => null);
    }
    await destroy();
  }

  Future send(List<int> data) async {
    _client.add(data);
    dynamic flush = await _client.flush();
    print(flush);
  }

  Future destroy() async {
    _client.destroy();
    await _socketListenerSubscription.cancel();
  }

  // ************************ Printer Commands ************************
  Future reset() async {
    await send(_generator.reset());
  }

  Future text(
    String text, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    bool containsChinese = false,
    int? maxCharsPerLine,
  }) async {
    await send(_generator.text(text, styles: styles, linesAfter: linesAfter, containsChinese: containsChinese, maxCharsPerLine: maxCharsPerLine));
  }

  Future setGlobalCodeTable(String codeTable) async {
    await send(_generator.setGlobalCodeTable(codeTable));
  }

  Future setGlobalFont(PosFontType font, {int? maxCharsPerLine}) async {
    await send(_generator.setGlobalFont(font, maxCharsPerLine: maxCharsPerLine));
  }

  Future setStyles(PosStyles styles, {bool isKanji = false}) async {
    await send(_generator.setStyles(styles, isKanji: isKanji));
  }

  Future rawBytes(List<int> cmd, {bool isKanji = false}) async {
    await send(_generator.rawBytes(cmd, isKanji: isKanji));
  }

  Future emptyLines(int n) async {
    await send(_generator.emptyLines(n));
  }

  Future feed(int n) async {
    await send(_generator.feed(n));
  }

  Future cut({PosCutMode mode = PosCutMode.full}) async {
    await send(_generator.cut(mode: mode));
  }

  Future printCodeTable({String? codeTable}) async {
    await send(_generator.printCodeTable(codeTable: codeTable));
  }

  Future beep({int n = 3, PosBeepDuration duration = PosBeepDuration.beep450ms}) async {
    await send(_generator.beep(n: n, duration: duration));
  }

  Future reverseFeed(int n) async {
    await send(_generator.reverseFeed(n));
  }

  Future row(List<PosColumn> cols) async {
    await send(_generator.row(cols));
  }

  Future image(Image imgSrc, {PosAlign align = PosAlign.center}) async {
    await send(_generator.image(imgSrc, align: align));
  }

  Future imageRaster(
    Image image, {
    PosAlign align = PosAlign.center,
    bool highDensityHorizontal = true,
    bool highDensityVertical = true,
    PosImageFn imageFn = PosImageFn.bitImageRaster,
  }) async {
    await send(_generator.imageRaster(
      image,
      align: align,
      highDensityHorizontal: highDensityHorizontal,
      highDensityVertical: highDensityVertical,
      imageFn: imageFn,
    ));
  }

  Future barcode(
    Barcode barcode, {
    int? width,
    int? height,
    BarcodeFont? font,
    BarcodeText textPos = BarcodeText.below,
    PosAlign align = PosAlign.center,
  }) async {
    await send(_generator.barcode(
      barcode,
      width: width,
      height: height,
      font: font,
      textPos: textPos,
      align: align,
    ));
  }

  Future qrcode(
    String text, {
    PosAlign align = PosAlign.center,
    QRSize size = QRSize.Size4,
    QRCorrection cor = QRCorrection.L,
  }) async {
    await send(_generator.qrcode(text, align: align, size: size, cor: cor));
  }

  Future drawer({PosDrawer pin = PosDrawer.pin2}) async {
    await send(_generator.drawer(pin: pin));
  }

  Future hr({String ch = '-', int? len, int linesAfter = 0}) async {
    await send(_generator.hr(ch: ch, linesAfter: linesAfter));
  }

  Future textEncoded(
    Uint8List textBytes, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    int? maxCharsPerLine,
  }) async {
    await send(_generator.textEncoded(
      textBytes,
      styles: styles,
      linesAfter: linesAfter,
      maxCharsPerLine: maxCharsPerLine,
    ));
  }
  // ************************ (end) Printer Commands ************************
}
