/// Somewhere to keep a secret that is not the database.
///
/// Exists so the PIN salt can be stored by the host in production and in
/// memory under test, without tests having to subclass a package whose method
/// signatures change between versions.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}
