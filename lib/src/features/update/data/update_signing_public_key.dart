import 'dart:convert';

import 'package:cryptography/cryptography.dart';

const updateSigningPublicKeyBase64 =
    'goFs+VajUYYWzmHbfPGEfT8TZ5IciPkvne0ktuC/Ycw=';

final updateSigningPublicKey = SimplePublicKey(
  base64Decode(updateSigningPublicKeyBase64),
  type: KeyPairType.ed25519,
);
