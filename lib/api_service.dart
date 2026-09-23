import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class ApiService {
  static const _base = 'https://api.twistmena.com/music';
  final http.Client _client;
  ApiService([http.Client? client]) : _client = client ?? http.Client();

  Map<String, String> baseHeaders() => {
    'user-agent': 'Twist-Mobile/9999 (Android; 12; Flutter; ar-AE)',
    'app_version': '9999', 'appversion': '9999', 'channel': 'mobileapp',
    'content-type': 'application/json', 'platform': 'android',
    'accept': 'application/json', 'accept-language': 'ar',
    'host': 'api.twistmena.com', 'device_id': 'flutter-android',
    'tgdeviceid': '26284330', 'device_token': '', 'tg-token': '',
    'tg-refresh-token': '', 'access-token': '',
    'sessionid': _sessionId(), 'accept-encoding': 'gzip',
  };

  static String _sessionId() {
    final r = Random();
    return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  Future<void> sendCode(String phone, Map<String, String> headers) async {
    final r = await _client.post(Uri.parse('$_base/Dlogin/sendCode'), headers: headers, body: jsonEncode({'dial': phone})).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw ApiException('فشل إرسال رمز التحقق (${r.statusCode})');
  }

  Future<Map<String, String>> verify(String phone, String code, Map<String, String> otpHeaders) async {
    final r = await _client.post(Uri.parse('$_base/Dlogin/verify'), headers: otpHeaders, body: jsonEncode({'dial': phone, 'verifyCode': code, 'socialServiceName': '', 'socialServiceToken': ''})).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw ApiException('رمز التحقق غير صحيح أو انتهت المحاولات');
    final data = jsonDecode(r.body);
    if (data is! Map) throw ApiException('استجابة تسجيل الدخول غير صالحة');
    final token = (data['token'] ?? data['authorization'] ?? r.headers['authorization'] ?? '').toString().replaceFirst('Bearer ', '');
    if (token.isEmpty) throw ApiException('لم يتم استلام رمز التوثيق');
    final h = Map<String, String>.from(otpHeaders);
    h['authorization'] = 'Bearer $token';
    h['access-token'] = (data['accessToken'] ?? '').toString();
    h['tg-token'] = (data['tgToken'] ?? data['tg_token'] ?? '').toString();
    h['tg-refresh-token'] = (data['tgRefreshToken'] ?? data['tg_refresh_token'] ?? '').toString();
    h['tgdeviceid'] = (data['tgDeviceId'] ?? data['tg_device_id'] ?? '26284330').toString();
    if (h['tg-token']!.isEmpty) {
      try {
        final p = await _client.post(Uri.parse('$_base/register/getProfile?api_token=${data['apiToken'] ?? data['api_token'] ?? _sessionId()}'), headers: h).timeout(const Duration(seconds: 10));
        if (p.statusCode == 200) {
          final pd = jsonDecode(p.body);
          h['tg-token'] = (pd['tgToken'] ?? pd['tg_token'] ?? '').toString();
          h['tg-refresh-token'] = (pd['tgRefreshToken'] ?? pd['tg_refresh_token'] ?? '').toString();
          h['tgdeviceid'] = (pd['tgDeviceId'] ?? pd['tg_device_id'] ?? '26284330').toString();
        }
      } catch (_) {}
    }
    return h;
  }

  Future<int> balance(Map<String, String> h) async {
    final r = await _client.get(Uri.parse('$_base/user/loyalty/balance/details'), headers: h).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw ApiException('تعذر جلب الرصيد');
    return int.tryParse((jsonDecode(r.body)['balance'] ?? 0).toString()) ?? 0;
  }

  Future<Map<String, dynamic>> achievements(Map<String, String> h) async {
    final r = await _client.get(Uri.parse('$_base/user/loyalty/achievements/v2'), headers: h).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw ApiException('تعذر جلب المهام');
    return Map<String, dynamic>.from(jsonDecode(r.body));
  }

  Future<CollectResult> collectAll(Map<String, String> h, void Function(String) onProgress) async {
    final data = await achievements(h); final actions = <Map<String, dynamic>>[];
    for (final category in (data['badges'] is List ? data['badges'] : const [])) {
      if (category is! Map) continue;
      for (final task in (category['badges'] is List ? category['badges'] : const [])) {
        if (task is Map && task['id'] != null && task['rewarded'] != true) actions.add({'id': task['id'], 'coins': task['coins'] ?? 0, 'title': task['title'] ?? task['id']});
      }
    }
    var earned = 0, completed = 0, failed = 0;
    for (var i = 0; i < actions.length; i++) {
      final a = actions[i]; onProgress('[${i + 1}/${actions.length}] ${a['title']}');
      try {
        final r = await _client.post(Uri.parse('$_base/loyalty/action/${a['id']}'), headers: h).timeout(const Duration(seconds: 10));
        if (r.statusCode == 200) { earned += int.tryParse(a['coins'].toString()) ?? 0; completed++; }
        else if (r.statusCode != 400) { failed++; if (r.statusCode == 403) break; }
      } catch (_) { failed++; break; }
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return CollectResult(actions.length, completed, failed, earned);
  }

  Future<List<dynamic>> history(Map<String, String> h) async {
    final all = <dynamic>[]; String token = '';
    do {
      final uri = Uri.parse('$_base/user/loyalty/history${token.isEmpty ? '' : '?paginationToken=$token'}');
      final r = await _client.get(uri, headers: h).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) break;
      final d = Map<String, dynamic>.from(jsonDecode(r.body)); final rows = d['data'];
      if (rows is! List || rows.isEmpty) break; all.addAll(rows); token = (d['paginationTokens'] ?? '').toString();
    } while (token.isNotEmpty);
    return all;
  }

  Future<List<PackageOption>> packages(Map<String, String> h, int balance, int remaining) async {
    if (remaining <= 0) return [];
    try {
      final r = await _client.get(Uri.parse('$_base/user/loyalty/packages'), headers: h).timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        final d = Map<String, dynamic>.from(jsonDecode(r.body)); final list = d['packages']?['E_AND'];
        if (list is List) return list.whereType<Map>().where((p) => p['available'] == true).map((p) => PackageOption(int.tryParse('${p['cost']}') ?? 0, int.tryParse('${p['value']}') ?? 0, '${p['id']}')).where((p) => p.cost <= balance && p.units <= remaining && p.cost > 0 && p.units > 0).toList()..sort((a,b) => a.cost.compareTo(b.cost));
      }
    } catch (_) {}
    const fallback = [(100,50,'EAND_50_UNITS_ID_9'),(200,100,'EAND_100_UNITS_ID_10'),(300,150,'EAND_150_UNITS_ID_11'),(600,300,'EAND_300_UNITS_ID_12'),(1000,500,'EAND_500_UNITS_ID_13'),(2000,1000,'EAND_1000_UNITS_ID_15')];
    return fallback.map((x) => PackageOption(x.$1,x.$2,x.$3)).where((p) => p.cost <= balance && p.units <= remaining).toList();
  }

  Future<void> redeem(Map<String, String> h, PackageOption p) async {
    final r = await _client.post(Uri.parse('$_base/loyalty/redeem/${p.code}'), headers: h).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw ApiException('فشل السحب (${r.statusCode})');
  }
}

class CollectResult { final int total, completed, failed, earned; CollectResult(this.total,this.completed,this.failed,this.earned); }
class PackageOption { final int cost, units; final String code; PackageOption(this.cost,this.units,this.code); }
