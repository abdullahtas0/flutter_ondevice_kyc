import 'package:flutter_ondevice_kyc/flutter_ondevice_kyc.dart';

String demoRejectLabel(RejectReason reason) {
  return switch (reason) {
    RejectReason.checksum => 'MRZ okundu, hane tutmadı. Kartı düz ve sabit tut.',
    RejectReason.badQuad => 'Köşeler çerçevede değil. Kartı düz tut.',
    RejectReason.noCard => 'Kimlik çerçevede görünmüyor.',
    RejectReason.unreadable => 'Alt üç satır net değil. Çerçeveyi doldurup sabit tut.',
  };
}
