// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:jibek_shared/jibek_shared.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/bake_taxi_splash.dart';

void main() => runApp(const JibekPassengerApp());

class JibekPassengerApp extends StatelessWidget {
  const JibekPassengerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(MediaQuery.textScalerOf(c).scale(1.0).clamp(0.85, 1.05))), child: child ?? const SizedBox.shrink()),
        title: 'Bake Taxi',
        debugShowCheckedModeBanner: false,
        theme: JibekTheme.light(),
        home: const BakeTaxiSplash(logoAsset: '../passenger_icon.png', subtitle: 'Ваш надёжный путь по Шымкенту', child: PassengerMapPage()),
      );
}

class PlaceResult {
  const PlaceResult(this.title, this.point);
  final String title;
  final LatLng point;
}

class PassengerMapPage extends StatefulWidget {
  const PassengerMapPage({super.key, this.initialService = JibekServiceType.cityTaxi, this.initialDestination, this.initialNote, this.openCategoryWindow = false, this.initialClass});
  final JibekServiceType initialService;
  final String? initialDestination, initialNote, initialClass;
  final bool openCategoryWindow;
  @override
  State<PassengerMapPage> createState() => _PassengerMapPageState();
}

class _PassengerMapPageState extends State<PassengerMapPage> {
  final _map = MapController();
  final _from = TextEditingController(text: 'ул. Тауке хана, 52');
  final _to = TextEditingController(text: 'ТРЦ «Mega Shymkent»');
  final _stop = TextEditingController();
  final _note = TextEditingController();
  bool _catWin = false, _addStop = false, _locating = false, _searching = false, _sending = false;
  final _shym = const LatLng(42.3154, 69.5869);
  LatLng? _fromPt = const LatLng(42.3154, 69.5869), _toPt = const LatLng(42.3238, 69.5965), _stopPt;
  List<LatLng> _route = const [LatLng(42.3154, 69.5869), LatLng(42.3185, 69.5910), LatLng(42.3215, 69.5940), LatLng(42.3238, 69.5965)];
  String _cls = 'Комфорт';
  String? _dist = '2.7 км', _dur = '8 мин';
  late JibekServiceType _srv;
  static const _api = String.fromEnvironment('JIBEK_API_URL'), _uid = String.fromEnvironment('JIBEK_DEV_USER_ID');

  @override
  void initState() {
    super.initState();
    _srv = widget.initialService;
    _cls = widget.initialClass ?? _cls;
    _catWin = widget.openCategoryWindow || _srv != JibekServiceType.cityTaxi;
    if (widget.initialNote?.trim().isNotEmpty ?? false) _note.text = widget.initialNote!.trim();
    if (widget.initialDestination?.trim().isNotEmpty ?? false) {
      _to.text = widget.initialDestination!.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _searchTo(); });
    }
  }

  @override
  void dispose() {
    for (final c in [_from, _to, _stop, _note]) c.dispose();
    super.dispose();
  }

  void _msg(String v) => mounted ? ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(v), behavior: SnackBarBehavior.floating)) : null;

  Future<void> _findMe() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return _msg('Включите геолокацию');
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return _msg('Нет доступа к GPS');
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
      final pt = LatLng(pos.latitude, pos.longitude);
      setState(() { _fromPt = pt; _from.text = 'Шымкент • ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}'; });
      _map.move(pt, 15);
      if (_toPt != null) await _buildRoute();
    } catch (_) {
      _msg('Ошибка GPS');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<PlaceResult?> _geo(String q) async {
    final res = await http.get(Uri.https('nominatim.openstreetmap.org', '/search', {'q': q, 'format': 'jsonv2', 'limit': '1', 'countrycodes': 'kz', 'accept-language': 'ru'}), headers: {'User-Agent': 'BakeTaxi/1.0'});
    if (res.statusCode != 200) return null;
    final d = jsonDecode(res.body) as List;
    if (d.isEmpty) return null;
    final lat = double.tryParse('${d[0]['lat']}'), lon = double.tryParse('${d[0]['lon']}');
    return (lat != null && lon != null) ? PlaceResult('${d[0]['display_name'] ?? q}', LatLng(lat, lon)) : null;
  }

  Future<void> _searchFrom() async {
    final q = _from.text.trim();
    if (q.isEmpty) return _findMe();
    setState(() => _searching = true);
    try {
      final r = await _geo('$q, Шымкент, Казахстан');
      if (r == null) return _msg('Адрес не найден');
      setState(() => _fromPt = r.point);
      _map.move(r.point, 14);
      if (_toPt != null) await _buildRoute();
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _searchTo() async {
    final q = _to.text.trim();
    if (q.isEmpty) return _msg('Введите адрес');
    setState(() => _searching = true);
    try {
      final r = await _geo('$q, Казахстан');
      if (r == null) return _msg('Адрес не найден');
      setState(() { _toPt = r.point; _to.text = r.title; });
      _map.move(r.point, 14);
      if (_fromPt != null) await _buildRoute();
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _searchStop() async {
    final q = _stop.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final r = await _geo('$q, Шымкент, Казахстан');
      if (r != null) {
        setState(() { _stopPt = r.point; _stop.text = r.title; });
        if (_fromPt != null && _toPt != null) await _buildRoute();
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _buildRoute() async {
    if (_fromPt == null || _toPt == null) return;
    setState(() => _searching = true);
    try {
      final pts = [_fromPt!, if (_addStop && _stopPt != null) _stopPt!, _toPt!];
      final res = await http.get(Uri.parse('https://project-osrm.org{pts.map((p) => '${p.longitude},${p.latitude}').join(';')}?overview=full&geometries=geojson'), headers: {'User-Agent': 'BakeTaxi/1.0'});
      if (res.statusCode != 200) return;
      final routes = (jsonDecode(res.body)['routes'] as List?) ?? [];
      if (routes.isEmpty) return;
      final list = routes[0]['geometry']['coordinates'] as List;
      final points = list.map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble())).toList();
      final m = (routes[0]['distance'] as num).toDouble(), s = (routes[0]['duration'] as num).toDouble();
      setState(() {
        _route = points;
        _dist = m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} км' : '${m.round()} м';
        _dur = '${(s / 60).ceil()} мин';
      });
      _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.fromLTRB(42, 130, 42, 340)));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  int get _fare => switch (_cls) { 'Комфорт' => 1200, 'Стандарт' => 1000, 'Бизнес' => 1800, 'Минивэн' => 2500, _ => 1000 };

  Future<void> _submitOrder() async {
    if (_fromPt == null || _toPt == null || _route.isEmpty) return _msg('Сначала постройте маршрут');
    if (_api.isEmpty || _uid.isEmpty) return _msg('Заказ оформлен локально');
    setState(() => _sending = true);
    final repo = DevJibekApiRepository(baseUrl: _api, devUserIdProvider: () async => _uid);
    try {
      final created = await repo.createOrder(JibekOrderRequest(
        id: 'local-draft',
        service: _srv,
        pickup: JibekGeoPoint(latitude: _fromPt!.latitude, longitude: _fromPt!.longitude, address: _from.text),
        destination: JibekGeoPoint(latitude: _toPt!.latitude, longitude: _toPt!.longitude, address: _to.text),
        stops: const [],
        createdAt: DateTime.now(),
        vehicleClass: _srv == JibekServiceType.cityTaxi ? _cls : null,
        priceKzt: _fare,
        boostCount: 0,
      ));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jibek_passenger_active_order_id', created.id);
      _msg('Заявка создана: ${created.id}');
    } catch (_) {
      _msg('Ошибка отправки');
    } finally {
      repo.close();
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _card(int i, String t, IconData ic) {
    final sel = _srv == JibekServiceType.cityTaxi && _cls == t;
    const pr = ['1 200 ₸', '1 000 ₸', '1 800 ₸', '2 500 ₸', 'По тарифу', 'По тарифу', 'По тарифу', 'По тарифу', 'По тарифу'];
    const img = ['comfort.png', 'econom.png', 'business.png', 'minivan.png', 'intercity.png', 'cargo.png', 'delivery.png', 'tow.png', 'tire.png'];
    return SizedBox(
      width: 112,
      child: GestureDetector(
        onTap: () {
          if (i <= 3) {
            setState(() { _srv = JibekServiceType.cityTaxi; _cls = ['Комфорт', 'Стандарт', 'Бизнес', 'Минивэн'][i]; });
          } else {
            const m = {4: JibekServiceType.intercity, 5: JibekServiceType.freight, 6: JibekServiceType.parcel, 7: JibekServiceType.towTruck, 8: JibekServiceType.mobileTire};
            Navigator.push(context, MaterialPageRoute(builder: (_) => PassengerMapPage(initialService: m[i]!, openCategoryWindow: true)));
          }
        },
        child: Container(
          height: 102,
