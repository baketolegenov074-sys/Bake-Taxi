// ignore_for_file: deprecated_member_use

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:jibek_shared/jibek_shared.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'passenger_home_page.dart';
import 'widgets/bake_taxi_splash.dart';

void main() => runApp(const JibekPassengerApp());

class JibekPassengerApp extends StatelessWidget {
  const JibekPassengerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Bake Taxi',
        debugShowCheckedModeBanner: false,
        theme: JibekTheme.light(),
        home: const BakeTaxiSplash(
          logoAsset: '../passenger_icon.png',
          subtitle: 'Ваш надёжный путь по Шымкенту',
          child: PassengerMapPage(),
        ),
      );
}

class PlaceResult {
  const PlaceResult(this.title, this.point);
  final String title;
  final LatLng point;
}

class PassengerMapPage extends StatefulWidget {
  const PassengerMapPage({
    super.key,
    this.initialService = JibekServiceType.cityTaxi,
    this.initialDestination,
    this.initialNote,
    this.openCategoryWindow = false,
    this.initialClass,
  });

  final JibekServiceType initialService;
  final String? initialDestination;
  final String? initialNote;
  final bool openCategoryWindow;
  final String? initialClass;

  @override
  State<PassengerMapPage> createState() => _PassengerMapPageState();
}

class _PassengerMapPageState extends State<PassengerMapPage> {
  static const _shymkent = LatLng(42.3154, 69.5869);
  static const _apiUrl = String.fromEnvironment('JIBEK_API_URL');
  static const _devUserId = String.fromEnvironment('JIBEK_DEV_USER_ID');

  final MapController _map = MapController();
  final TextEditingController _from = TextEditingController(text: 'ул. Тауке хана, 52');
  final TextEditingController _to = TextEditingController(text: 'ТРЦ «Mega Shymkent»');
  final TextEditingController _stop = TextEditingController();
  final TextEditingController _note = TextEditingController();

  LatLng? _fromPoint = _shymkent;
  LatLng? _toPoint = const LatLng(42.3238, 69.5965);
  LatLng? _stopPoint;
  List<LatLng> _route = const [
    _shymkent,
    LatLng(42.3185, 69.5910),
    LatLng(42.3238, 69.5965),
  ];

  late JibekServiceType _service;
  String _vehicleClass = 'Комфорт';
  String _payment = 'Наличные';
  bool _addStop = false;
  bool _searching = false;
  bool _locating = false;
  bool _sending = false;
  String _distance = '2.7 км';
  String _duration = '8 мин';

  @override
  void initState() {
    super.initState();
    _service = widget.initialService;
    _vehicleClass = widget.initialClass ?? 'Комфорт';
    if (widget.initialDestination?.trim().isNotEmpty ?? false) {
      _to.text = widget.initialDestination!.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchDestination();
      });
    }
    if (widget.initialNote?.trim().isNotEmpty ?? false) {
      _note.text = widget.initialNote!.trim();
    }
    if (widget.openCategoryWindow && _service != JibekServiceType.cityTaxi) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openServicePicker(_service);
      });
    }
  }

  @override
  void dispose() {
    _map.dispose();
    _from.dispose();
    _to.dispose();
    _stop.dispose();
    _note.dispose();
    super.dispose();
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value), behavior: SnackBarBehavior.floating),
    );
  }

  Future<PlaceResult?> _geocode(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'jsonv2',
      'limit': '1',
      'countrycodes': 'kz',
      'accept-language': 'ru',
    });
    final response = await http.get(uri, headers: {
      'User-Agent': 'BakeTaxiPassenger/1.0',
      'Accept': 'application/json',
    });
    if (response.statusCode != 200) {
      throw Exception('Сервис поиска адресов временно недоступен');
    }
    final results = jsonDecode(response.body) as List<dynamic>;
    if (results.isEmpty) return null;
    final item = results.first as Map<String, dynamic>;
    final lat = double.tryParse(item['lat']?.toString() ?? '');
    final lon = double.tryParse(item['lon']?.toString() ?? '');
    if (lat == null || lon == null) return null;
    return PlaceResult(
      item['display_name']?.toString() ?? query,
      LatLng(lat, lon),
    );
  }

  Future<void> _searchFrom() async {
    final query = _from.text.trim();
    if (query.isEmpty) return _findMe();
    setState(() => _searching = true);
    try {
      final result = await _geocode('$query, Шымкент, Казахстан');
      if (result == null) {
        _message('Адрес отправления не найден');
        return;
      }
      setState(() => _fromPoint = result.point);
      _map.move(result.point, 15);
      await _buildRoute();
    } catch (error) {
      _message('Ошибка поиска адреса: $error');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _searchDestination() async {
    final query = _to.text.trim();
    if (query.isEmpty) {
      _message('Введите адрес назначения');
      return;
    }
    setState(() => _searching = true);
    try {
      final result = await _geocode('$query, Казахстан');
      if (result == null) {
        _message('Адрес назначения не найден');
        return;
      }
      setState(() {
        _toPoint = result.point;
        _to.text = result.title;
      });
      _map.move(result.point, 15);
      await _buildRoute();
    } catch (error) {
      _message('Ошибка поиска адреса: $error');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _searchStop() async {
    final query = _stop.text.trim();
    if (query.isEmpty) {
      _message('Введите промежуточный адрес');
      return;
    }
    setState(() => _searching = true);
    try {
      final result = await _geocode('$query, Шымкент, Казахстан');
      if (result == null) {
        _message('Остановка не найдена');
        return;
      }
      setState(() {
        _stopPoint = result.point;
        _stop.text = result.title;
      });
      await _buildRoute();
    } catch (error) {
      _message('Ошибка поиска остановки: $error');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _findMe() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _message('Включите геолокацию на телефоне');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _message('Разрешите доступ к геолокации');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      final point = LatLng(position.latitude, position.longitude);
      setState(() {
        _fromPoint = point;
        _from.text =
            'Шымкент • ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      });
      _map.move(point, 15);
      await _buildRoute();
    } catch (error) {
      _message('Не удалось определить местоположение: $error');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _buildRoute() async {
    final start = _fromPoint;
    final end = _toPoint;
    if (start == null || end == null) return;
    setState(() => _searching = true);
    try {
      final points = <LatLng>[
        start,
        if (_addStop && _stopPoint != null) _stopPoint!,
        end,
      ];
      final coordinates = points
          .map((point) => '${point.longitude},${point.latitude}')
          .join(';');
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '$coordinates?overview=full&geometries=geojson',
      );
      final response = await http.get(uri, headers: {
        'User-Agent': 'BakeTaxiPassenger/1.0',
      });
      if (response.statusCode != 200) {
        throw Exception('Сервис маршрутов вернул ошибку ${response.statusCode}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>? ?? [];
      if (routes.isEmpty) {
        _message('Маршрут не найден');
        return;
      }
      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final coordinatesList = geometry['coordinates'] as List<dynamic>;
      final routePoints = coordinatesList.map((pair) {
        final item = pair as List<dynamic>;
        return LatLng(
          (item[1] as num).toDouble(),
          (item[0] as num).toDouble(),
        );
      }).toList();
      final meters = (route['distance'] as num).toDouble();
      final seconds = (route['duration'] as num).toDouble();
      if (!mounted) return;
      setState(() {
        _route = routePoints;
        _distance = meters >= 1000
            ? '${(meters / 1000).toStringAsFixed(1)} км'
            : '${meters.round()} м';
        _duration = '${(seconds / 60).ceil()} мин';
      });
      if (routePoints.length > 1) {
        _map.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(routePoints),
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
        ));
      }
    } catch (error) {
      _message('Не удалось построить маршрут: $error');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  int get _fare => switch (_vehicleClass) {
        'Эконом' => 1000,
        'Комфорт' => 1200,
        'Бизнес' => 1800,
        'Вместе' => 800,
        _ => 2500,
      };

  String get _serviceTitle => switch (_service) {
        JibekServiceType.cityTaxi => 'Такси',
        JibekServiceType.parcel => 'Доставка',
        JibekServiceType.freight => 'Грузовой',
        JibekServiceType.intercity => 'Межгород',
        JibekServiceType.towTruck => 'Эвакуатор',
        JibekServiceType.mobileTire => 'Шиномонтаж',
      };

  Future<void> _openTariff(String title, String asset, String price) async {
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => TariffDetailPage(
          title: title,
          asset: asset,
          price: price,
          selected: _vehicleClass == title,
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _vehicleClass = selected;
        _service = JibekServiceType.cityTaxi;
      });
    }
  }

  Future<void> _openServicePicker(JibekServiceType service) async {
    if (service == JibekServiceType.intercity) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const IntercityPage()),
      );
      return;
    }
    final selected = await Navigator.of(context).push<JibekServiceType>(
      MaterialPageRoute(
        builder: (_) => ServiceSelectionPage(initialService: service),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _service = selected);
    }
  }

  Future<void> _submitOrder() async {
    if (_fromPoint == null || _toPoint == null) {
      _message('Укажите адреса отправления и назначения');
      return;
    }
    if (_apiUrl.isEmpty || _devUserId.isEmpty) {
      _message('Сервер заказов ещё не подключён. Заказ не отправлен.');
      return;
    }
    setState(() => _sending = true);
    final repository = DevJibekApiRepository(
      baseUrl: _apiUrl,
      devUserIdProvider: () async => _devUserId,
    );
    try {
      final order = await repository.createOrder(JibekOrderRequest(
        id: 'bake-${DateTime.now().microsecondsSinceEpoch}',
        service: _service,
        pickup: JibekGeoPoint(
          latitude: _fromPoint!.latitude,
          longitude: _fromPoint!.longitude,
          address: _from.text,
        ),
        destination: JibekGeoPoint(
          latitude: _toPoint!.latitude,
          longitude: _toPoint!.longitude,
          address: _to.text,
        ),
        stops: const [],
        createdAt: DateTime.now(),
        vehicleClass: _service == JibekServiceType.cityTaxi ? _vehicleClass : null,
        priceKzt: _fare,
        boostCount: 0,
      ));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jibek_passenger_active_order_id', order.id);
      _message('Заказ отправлен: ${order.id}');
    } catch (error) {
      _message('Не удалось отправить заказ: $error');
    } finally {
      repository.close();
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _addressField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required Color color,
    required VoidCallback onSearch,
    Widget? trailing,
  }) {
    return Row(children: [
      Icon(icon, color: color, size: 19),
      const SizedBox(width: 7),
      SizedBox(
        width: 54,
        child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      ),
      Expanded(
        child: TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => onSearch(),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 9),
          ),
        ),
      ),
      if (trailing != null) trailing,
      IconButton(
        onPressed: _searching ? null : onSearch,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.search_rounded, size: 20),
      ),
    ]);
  }

  Widget _tariffCard(String title, String subtitle, String asset, String price) {
    final selected = _vehicleClass == title && _service == JibekServiceType.cityTaxi;
    return GestureDetector(
      onTap: () => _openTariff(title, asset, price),
      child: Container(
        width: 112,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF8DD) : const Color(0xFFF5F6F8),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? const Color(0xFFFFC928) : const Color(0xFFE4E7EC),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Center(
              child: Image.asset(
                'assets/cars/$asset',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.directions_car_rounded,
                  size: 42,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          ),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
          const SizedBox(height: 3),
          Text(price, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
        ]),
      ),
    );
  }

  Widget _categoryChip(String title, IconData icon, JibekServiceType service) {
    final active = _service == service;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ActionChip(
        avatar: Icon(icon, size: 16, color: active ? Colors.white : const Color(0xFF263445)),
        label: Text(title, style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: active ? Colors.white : const Color(0xFF263445),
        )),
        backgroundColor: active ? const Color(0xFF263445) : const Color(0xFFF1F3F5),
        side: BorderSide.none,
        onPressed: () => _openServicePicker(service),
      ),
    );
  }

  Widget _mapView() {
    final markers = <Marker>[
      if (_fromPoint != null)
        Marker(
          point: _fromPoint!,
          width: 38,
          height: 38,
          child: const Icon(Icons.location_on_rounded, color: Color(0xFF159447), size: 36),
        ),
      if (_stopPoint != null && _addStop)
        Marker(
          point: _stopPoint!,
          width: 36,
          height: 36,
          child: const Icon(Icons.location_on_rounded, color: Colors.orange, size: 34),
        ),
      if (_toPoint != null)
        Marker(
          point: _toPoint!,
          width: 40,
          height: 40,
          child: const Icon(Icons.location_on_rounded, color: Color(0xFFD83232), size: 38),
        ),
    ];
    return ClipRect(
      child: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: const MapOptions(initialCenter: _shymkent, initialZoom: 14),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'kz.baketaxi.client',
            ),
            if (_route.length > 1)
              PolylineLayer(polylines: [
                Polyline(
                  points: _route,
                  strokeWidth: 5,
                  color: const Color(0xFF1769D2),
                  borderStrokeWidth: 2,
                  borderColor: Colors.white,
                ),
              ]),
            MarkerLayer(markers: markers),
          ],
        ),
        Positioned(
          left: 12,
          top: 12,
          child: _mapLabel('Подача', '2 мин', Icons.local_taxi_rounded),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: _mapLabel(_duration, _distance, Icons.route_rounded),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: FloatingActionButton.small(
            heroTag: 'locate_me',
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF172B3A),
            onPressed: _locating ? null : _findMe,
            child: _locating
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location_rounded),
          ),
        ),
      ]),
    );
  }

  Widget _mapLabel(String title, String value, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17, color: const Color(0xFF263445)),
          const SizedBox(width: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
            Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
          ]),
        ]),
      );

  Widget _orderPanel() => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, -3))],
        ),
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 7, 12, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(
                  child: Container(
                    width: 34,
                    height: 4,
                    decoration: BoxDecoration(color: const Color(0xFFD7DCE2), borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(height: 5),
                _addressField(
                  label: 'Откуда',
                  controller: _from,
                  icon: Icons.trip_origin_rounded,
                  color: const Color(0xFF159447),
                  onSearch: _searchFrom,
                ),
                const Divider(height: 1),
                _addressField(
                  label: 'Куда',
                  controller: _to,
                  icon: Icons.location_on_rounded,
                  color: const Color(0xFFD83232),
                  onSearch: _searchDestination,
                  trailing: IconButton(
                    tooltip: 'Добавить остановку',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _addStop = !_addStop),
                    icon: Icon(_addStop ? Icons.remove_circle_outline : Icons.add_circle_outline, size: 20),
                  ),
                ),
                if (_addStop) ...[
                  const Divider(height: 1),
                  _addressField(
                    label: 'Заезд',
                    controller: _stop,
                    icon: Icons.more_horiz,
                    color: Colors.orange,
                    onSearch: _searchStop,
                  ),
                ],
                const SizedBox(height: 5),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _categoryChip('Такси', Icons.local_taxi_rounded, JibekServiceType.cityTaxi),
                      _categoryChip('Доставка / Груз', Icons.local_shipping_rounded, JibekServiceType.freight),
                      _categoryChip('Спецтехника', Icons.car_repair_rounded, JibekServiceType.towTruck),
                      _categoryChip('Межгород', Icons.route_rounded, JibekServiceType.intercity),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Row(children: [
                  const Expanded(
                    child: Text('Выберите тариф', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                  ),
                  Text(_serviceTitle, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                ]),
                const SizedBox(height: 6),
                SizedBox(
                  height: 132,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _tariffCard('Вместе', 'Попутчики', 'intercity.png', '800 ₸'),
                      _tariffCard('Эконом', 'от 4 мин', 'econom.png', '1 000 ₸'),
                      _tariffCard('Комфорт', 'от 2 мин', 'comfort.png', '1 200 ₸'),
                      _tariffCard('Бизнес', 'от 5 мин', 'business.png', '1 800 ₸'),
                      _tariffCard('Минивэн', 'от 6 мин', 'minivan.png', '2 500 ₸'),
                    ],
                  ),
                ),
                if (_service != JibekServiceType.cityTaxi)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Выбрана услуга: $_serviceTitle',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 5, 12, 7),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _payment = _payment == 'Наличные' ? 'Карта' : 'Наличные'),
                  icon: Icon(_payment == 'Наличные' ? Icons.payments_outlined : Icons.credit_card_rounded, size: 17),
                  label: Text(_payment, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF263445),
                    side: const BorderSide(color: Color(0xFFD9DEE5)),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _sending || _searching ? null : _submitOrder,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC928),
                    foregroundColor: const Color(0xFF172B3A),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  child: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('Заказать • $_fare ₸', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF4F6F8),
        body: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            final mapHeight = constraints.maxHeight * 0.55;
            return Column(children: [
              SizedBox(height: mapHeight, width: double.infinity, child: _mapView()),
              Expanded(child: _orderPanel()),
            ]);
          }),
        ),
      );
}

class TariffDetailPage extends StatelessWidget {
  const TariffDetailPage({
    super.key,
    required this.title,
    required this.asset,
    required this.price,
    required this.selected,
  });

  final String title;
  final String asset;
  final String price;
  final bool selected;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Выбор тарифа'),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF172B3A),
          elevation: 0,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const SizedBox(height: 20),
              Expanded(
                child: Image.asset(
                  'assets/cars/$asset',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.directions_car_rounded, size: 120),
                ),
              ),
              Text(title, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(price, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC928),
                    foregroundColor: const Color(0xFF172B3A),
                  ),
                  onPressed: () => Navigator.pop(context, title),
                  child: Text(selected ? 'Выбран • Подтвердить' : 'Выбрать тариф'),
                ),
              ),
            ]),
          ),
        ),
      );
}

class ServiceSelectionPage extends StatelessWidget {
  const ServiceSelectionPage({super.key, required this.initialService});
  final JibekServiceType initialService;

  @override
  Widget build(BuildContext context) {
    final options = <(String, String, String, JibekServiceType)>[
      ('Доставка / Посылка', 'delivery.png', 'от 1 000 ₸', JibekServiceType.parcel),
      ('Грузовой', 'cargo.png', 'По тарифу', JibekServiceType.freight),
      ('Эвакуатор', 'tow.png', 'По тарифу', JibekServiceType.towTruck),
      ('Шиномонтаж', 'tire.png', 'По тарифу', JibekServiceType.mobileTire),
    ];
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Выбор услуги'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF172B3A),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: options.map((option) => Card(
          color: const Color(0xFFF7F8FA),
          elevation: 0,
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: SizedBox(
              width: 76,
              height: 66,
              child: Image.asset(
                'assets/cars/${option.$2}',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.local_shipping_rounded, size: 36),
              ),
            ),
            title: Text(option.$1, style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text(option.$3),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.pop(context, option.$4),
          ),
        )).toList(),
      ),
    );
  }
}
