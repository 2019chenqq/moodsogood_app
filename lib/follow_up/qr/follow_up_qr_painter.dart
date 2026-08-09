import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

class FollowUpQrPainter extends CustomPainter {
  FollowUpQrPainter(String data)
      : _image = QrImage(
          QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
        );

  final QrImage _image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.src);
    final scale = size.shortestSide / _image.moduleCount;
    final paint = Paint()..color = Colors.black;
    for (var y = 0; y < _image.moduleCount; y++) {
      for (var x = 0; x < _image.moduleCount; x++) {
        if (_image.isDark(y, x)) {
          canvas.drawRect(
            Rect.fromLTWH(
              x * scale,
              y * scale,
              scale.ceilToDouble(),
              scale.ceilToDouble(),
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant FollowUpQrPainter oldDelegate) => false;
}
