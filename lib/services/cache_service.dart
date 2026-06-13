

class CacheService {
  static final Map<String, dynamic> _memoryCache = {};

  static Future<void> save(String key, dynamic data) async {
    _memoryCache[key] = data;
  }

  static Future<dynamic> load(String key) async {
    return _memoryCache[key];
  }

  static Future<void> clear(String key) async {
    _memoryCache.remove(key);
  }
}
