import 'package:web/web.dart' as web;

import 'secret_store.dart';

/// The origin's own storage, which is where a browser keeps everything.
///
/// **The separation a tablet gets is not available here, and pretending
/// otherwise would be worse than saying so.** The board's database and this
/// salt live under the same origin and are cleared by the same menu item;
/// there is no keystore behind either of them and no copy of the database to
/// take away without taking the salt with it.
///
/// `flutter_secure_storage` does have a web implementation, and it also ends
/// up in this same storage — with the added condition that it needs a secure
/// context for `crypto.subtle`, so a build served over plain HTTP on a local
/// network would fail at the point somebody tries to set a PIN. Trading a
/// security property that does not exist here for a caregiver screen that
/// opens is the right way round.
///
/// The PIN still does its job, which was always modest: it keeps an AAC user
/// and their curious sibling out of the editor, where a careless drag undoes
/// months of learned positions.
class DeviceSecretStore implements SecretStore {
  const DeviceSecretStore();

  @override
  Future<String?> read(String key) async =>
      web.window.localStorage.getItem(key);

  @override
  Future<void> write(String key, String value) async =>
      web.window.localStorage.setItem(key, value);
}
