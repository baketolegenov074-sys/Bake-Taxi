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
        builder: (context, child) {
          final systemScale = MediaQuery.textScalerOf(context).scale(1.0).clamp(0.85, 1.05);
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(systemScale)),
            child: child ?? const SizedBox.shrink(),
          );
        },
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
  final MapController _mapController = MapController();
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  final FocusNode _fromFocusNode = FocusNode();
  final FocusNode _toFocusNode = FocusNode();
  bool _addressFieldFocused = false;
  bool _showCategoryWindow = false;
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _stopController = TextEditingController();
  bool _addStop = false;
  LatLng? _stopPoint;
  final String _paymentMethod = 'Наличные';
  final bool _childSeat = false;
  final bool _needMovers = false;
  final bool _boostSelected = false;
  final int _intercitySeats = 1;
  final String _intercityCity = 'Туркестан';
  final LatLng _shymkent = const LatLng(42.3154, 69.5869);

  LatLng? _fromPoint;
  LatLng? _toPoint;
  List<LatLng> _route = [];
  String _class = 'Комфорт';
  late JibekServiceType _service;
  String? _distanceLabel;
  String? _durationLabel;
  bool _locating = false;
  bool _searching = false;
  bool _sendingOrder = false;
  bool _refreshingOrder = false;
  bool _cancellingOrder = false;
  JibekOrderRequest? _createdOrder;
  static const _apiUrl = String.fromEnvironment('JIBEK_API_URL');
  static const _devUserId = String.fromEnvironment('JIBEK_DEV_USER_ID');

  @override
  void initState() {
    super.initState();
    _service = widget.initialService;
    _class = widget.initialClass ?? _class;
    _showCategoryWindow = widget.openCategoryWindow || widget.initialService != JibekServiceType.cityTaxi;
    _fromController.text = 'ул. Тауке хана, 52';
    _toController.text = 'ТРЦ «Mega Shymkent»';
    _fromPoint = const LatLng(42.3154, 69.5869);
    _toPoint = const LatLng(42.3238, 69.5965);
    _distanceLabel = '2.7 км';
    _durationLabel = '8 мин';
    _route = const [
      LatLng(42.3154, 69.5869),
      LatLng(42.3185, 69.5910),
      LatLng(42.3215, 69.5940),
      LatLng(42.3238, 69.5965),
    ];

    _fromFocusNode.addListener(_onAddressFocusChanged);
    _toFocusNode.addListener(_onAddressFocusChanged);
    final initialNote = widget.initialNote?.trim();
    if (initialNote != null && initialNote.isNotEmpty) {
      _noteController.text = initialNote;
    }
    final destination = widget.initialDestination?.trim();
    if (destination != null && destination.isNotEmpty) {
      _toController.text = destination;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchDestination();
      });
    }
    _restoreSavedOrder();
  }

  void _onAddressFocusChanged() {
    final focused = _fromFocusNode.hasFocus || _toFocusNode.hasFocus;
    if (mounted && focused != _addressFieldFocused) {
      setState(() => _addressFieldFocused = focused);
    }
  }

  @override
  void dispose() {
    _fromFocusNode.removeListener(_onAddressFocusChanged);
    _toFocusNode.removeListener(_onAddressFocusChanged);
    _fromFocusNode.dispose();
    _toFocusNode.dispose();
    _fromController.dispose();
    _toController.dispose();
    _noteController.dispose();
    _stopController.dispose();
    super.dispose();
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value), behavior: SnackBarBehavior.floating),
    );
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
        _message('Разрешите доступ к местоположению в настройках телефона');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      final point = LatLng(position.latitude, position.longitude);
      final reverseUri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': position.latitude.toString(),
        'lon': position.longitude.toString(),
        'format': 'jsonv2',
        'accept-language': 'ru',
        'zoom': '18',
      });
      final reverseResponse = await http.get(reverseUri, headers: {
        'User-Agent': 'BakeTaxiPassenger/1.0',
        'Accept': 'application/json',
      });
      var addressText = '';
      if (reverseResponse.statusCode == 200) {
        final reverseData = jsonDecode(reverseResponse.body) as Map<String, dynamic>;
        final address = reverseData['address'] as Map<String, dynamic>? ?? {};
        final road = address['road'] ?? address['pedestrian'] ?? address['residential'];
        final house = address['house_number'];
        final district = address['suburb'] ?? address['neighbourhood'];
        final city = address['city'] ?? address['town'] ?? address['village'] ?? 'Шымкент';
        addressText = [
          if (road != null) road,
          if (house != null) house,
          if (district != null) district,
          city,
        ].map((part) => part.toString()).join(', ');
        if (addressText.isEmpty) {
          addressText = reverseData['display_name']?.toString() ?? '';
        }
      }
      if (addressText.isEmpty) {
        addressText = 'Шымкент • ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      }
      setState(() {
        _fromPoint = point;
        _fromController.text = addressText;
      });
      _mapController.move(point, 15);
      if (_toPoint != null) await _buildRoute();
    } catch (_) {
      _message('Не удалось определить местоположение');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
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
      'User-Agent': 'JibekZholyPassenger/1.0 (mobile app)',
      'Accept': 'application/json',
    });
    if (response.statusCode != 200) {
      throw Exception('Сервис поиска адресов временно недоступен');
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    if (data.isEmpty) return null;
    final item = data.first as Map<String, dynamic>;
    final lat = double.tryParse(item['lat']?.toString() ?? '');
    final lon = double.tryParse(item['lon']?.toString() ?? '');
    if (lat == null || lon == null) return null;
    return PlaceResult(
      item['display_name']?.toString() ?? query,
      LatLng(lat, lon),
    );
  }
  Future<void> _searchStop() async {
    final query = _stopController.text.trim();
    if (!_addStop) return;
    if (query.isEmpty) {
      _message('Введите адрес промежуточной остановки');
      return;
    }
    setState(() => _searching = true);
    try {
      final result = await _geocode('$query, Шымкент, Казахстан');
      if (result == null) {
        _message('Промежуточная остановка не найдена');
        return;
      }
      setState(() {
        _stopPoint = result.point;
        _stopController.text = result.title;
        _route = [];
        _distanceLabel = null;
        _durationLabel = null;
      });
      _mapController.move(result.point, 14);
      if (_fromPoint != null && _toPoint != null) await _buildRoute();
    } catch (e) {
      _message('Ошибка поиска остановки: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _searchDestination() async {
    final query = _toController.text.trim();
    if (query.isEmpty) {
      _message('Введите адрес или название места');
      return;
    }
    setState(() => _searching = true);
    try {
      final result = await _geocode('$query, Казахстан');
      if (result == null) {
        _message('Адрес не найден. Уточните название или улицу.');
        return;
      }
      setState(() {
        _toPoint = result.point;
        _toController.text = result.title;
        _route = [];
        _distanceLabel = null;
        _durationLabel = null;
      });
      _mapController.move(result.point, 14);
      if (_fromPoint != null) await _buildRoute();
    } catch (e) {
      _message('Ошибка поиска адреса: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _buildRoute() async {
    final start = _fromPoint;
    final end = _toPoint;
    if (start == null || end == null) {
      _message('Сначала укажите точку отправления и назначения');
      return;
    }
    setState(() => _searching = true);
    try {
      final routePoints = <LatLng>[
        start,
        if (_addStop && _stopPoint != null) _stopPoint!,
        end,
      ];
      final coordinatesQuery = routePoints
          .map((point) => '${point.longitude},${point.latitude}')
          .join(';');
      final uri = Uri.parse(
        'https://project-osrm.org'
        '$coordinatesQuery?overview=full&geometries=geojson',
      );
      final response = await http.get(uri, headers: {
        'User-Agent': 'JibekZholyPassenger/1.0',
      });
      if (response.statusCode != 200) throw Exception('Ошибка построения маршрута');
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = json['routes'] as List<dynamic>? ?? [];
      if (routes.isEmpty) {
        _message('Маршрут не найден');
        return;
      }
      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List<dynamic>;
      if (coordinates.length < 2) {
        _message('Маршрут получен без координат. Попробуйте выбрать адрес ещё раз.');
        return;
      }
      final points = coordinates.map((pair) {
        final p = pair as List<dynamic>;
        return LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble());
      }).toList();
      final meters = (route['distance'] as num).toDouble();
      final seconds = (route['duration'] as num).toDouble();
      setState(() {
        _route = points;
        _distanceLabel = meters >= 1000
            ? '${(meters / 1000).toStringAsFixed(1)} км'
            : '${meters.round()} м';
        _durationLabel = '${(seconds / 60).ceil()} мин';
      });
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.fromLTRB(42, 130, 42, 340),
      ));
    } catch (e) {
      _message('Не удалось построить маршрут: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectMapPoint(TapPosition tapPosition, LatLng point) {
    setState(() {
      _toPoint = point;
      _toController.text =
          '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
      _route = [];
      _distanceLabel = null;
      _durationLabel = null;
    });
    if (_fromPoint != null) _buildRoute();
  }

  void _selectOffer(int index) {
    if (index >= 0 && index <= 3) {
      const classes = ['Комфорт', 'Стандарт', 'Бизнес', 'Минивэн'];
      setState(() {
        _service = JibekServiceType.cityTaxi;
        _class = classes[index];
      });
      return;
    }
    late final JibekServiceType service;
    switch (index) {
      case 4:
        service = JibekServiceType.intercity;
        break;
      case 5:
        service = JibekServiceType.freight;
        break;
      case 6:
        service = JibekServiceType.parcel;
        break;
      case 7:
        service = JibekServiceType.towTruck;
        break;
      case 8:
        service = JibekServiceType.mobileTire;
        break;
      default:
        return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PassengerMapPage(
        initialService: service,
        openCategoryWindow: true,
      ),
    ));
  }

  void _openCategory(JibekServiceType service) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PassengerMapPage(
        initialService: service,
        openCategoryWindow: true,
      ),
    ));
  }

  void _closeCategoryWindow() {
    if (widget.openCategoryWindow) {
      Navigator.of(context).pop();
    } else {
      setState(() => _showCategoryWindow = false);
    }
  }

  int get _estimatedTaxiFare {
    switch (_class) {
      case 'Комфорт':
        return 1200;
      case 'Стандарт':
        return 1000;
      case 'Бизнес':
        return 1800;
      case 'Минивэн':
        return 2500;
      default:
        return 1000;
    }
  }

  String get _orderButtonLabel {
    if (_searching || _sendingOrder) return 'Подождите…';
    switch (_service) {
      case JibekServiceType.cityTaxi:
        return 'Заказать такси';
      case JibekServiceType.intercity:
        return 'Заказать межгород';
      case JibekServiceType.freight:
        return 'Заказать грузовой';
      case JibekServiceType.parcel:
        return 'Отправить посылку';
      case JibekServiceType.towTruck:
      case JibekServiceType.mobileTire:
        return 'Вызвать помощь';
    }
  }

  Widget _offerCard(int index, String title, String subtitle, IconData icon, {double height = 102}) {
    final selected = _service == JibekServiceType.cityTaxi && _class == title;
    const prices = [
      '1 200 ₸',
      '1 000 ₸',
      '1 800 ₸',
      '2 500 ₸',
      'По тарифу',
      'По тарифу',
      'По тарифу',
      'По тарифу',
      'По тарифу',
    ];
    const assets = [
      'comfort.png',
      'econom.png',
      'business.png',
      'minivan.png',
      'intercity.png',
      'cargo.png',
      'delivery.png',
      'tow.png',
      'tire.png',
    ];
    return SizedBox(
      width: 112,
      child: GestureDetector(
        onTap: () => _selectOffer(index),
        child: Container(
          height: height,
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 7),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFFDF4) : const Color(0xFFF3F5FB),
            border: Border.all(
              color: selected ? const Color(0xFFFFC928) : const Color(0xFFE2E6F0),
              width: selected ? 2.5 : 1,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Stack(children: [
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Expanded(
                child: Image.asset(
                  'assets/cars/${assets[index]}',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(icon, size: 38, color: const Color(0xFF4B5563)),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF1F2937)),
              ),
              const SizedBox(height: 1),
              Text(
                prices[index],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF111827)),
              ),
            ]),
            if (selected)
              const Positioned(
                right: 0,
                top: 0,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: Color(0xFFFFC928),
                  child: Icon(Icons.check_rounded, size: 14, color: Color(0xFF172B3A)),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _passengerOrderPanel(JibekOrderRequest order) {
    final completed = order.status == JibekOrderStatus.completed;
    final cancelled = order.status == JibekOrderStatus.cancelled;
    final active = !completed && !cancelled;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: completed ? const Color(0xFFEAF7EE) : const Color(0xFFF3F6FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: completed ? const Color(0xFFB9E2C5) : const Color(0xFFE0E6EF)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            completed
                ? Icons.check_circle_rounded
                : cancelled
  Widget _quickTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color tint,
    VoidCallback onTap,
  ) =>
      Material(
        color: tint,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 22, color: const Color(0xFF172B3A)),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF172B3A)),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 8.5, color: Color(0xFF374151)),
              ),
            ]),
          ),
        ),
      );

  Widget _metricTile(
    IconData icon,
    String value,
    String label, {
    bool showInfo = false,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F5FA),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(children: [
          Icon(icon, color: const Color(0xFF172B3A), size: 19),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF111827)),
                    ),
                  ),
                  if (showInfo) const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF1E3A8A)),
                ]),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9.5, color: Color(0xFF4B5563)),
                ),
              ],
            ),
          ),
        ]),
      );

  Widget _mapBadge({required IconData icon, required String topText, required String bottomText}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: const Color(0xFF1D4ED8)),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(topText, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF111827))),
          Text(bottomText, style: const TextStyle(fontSize: 10, color: Color(0xFF4B5563))),
        ]),
      ]),
    );
  }

  Widget _buildCategoryWindow() {
    final title = switch (_service) {
      JibekServiceType.cityTaxi => _class,
      JibekServiceType.parcel => 'Доставка',
      JibekServiceType.freight => 'Грузовой',
      JibekServiceType.towTruck => 'Эвакуатор',
      JibekServiceType.mobileTire => 'Шиномонтаж',
      JibekServiceType.intercity => 'Межгород',
    };
    final icon = switch (_service) {
      JibekServiceType.cityTaxi => Icons.local_taxi_rounded,
      JibekServiceType.parcel => Icons.inventory_2_rounded,
      JibekServiceType.freight => Icons.local_shipping_rounded,
      JibekServiceType.towTruck => Icons.car_crash_rounded,
      JibekServiceType.mobileTire => Icons.tire_repair_rounded,
      JibekServiceType.intercity => Icons.route_rounded,
    };
    const places = [
      ('Коктал 26', 'Шымкент', '40 мин'),
      ('Жиделибайсына 92', 'Шымкент', '14 мин'),
      ('Алаш', 'Темирлановское ш., 198/7', '12 мин'),
    ];
    return Container(
      color: Colors.white.withOpacity(0.96),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                IconButton(
                  tooltip: 'Назад',
                  onPressed: _closeCategoryWindow,
                  icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF172B3A)),
                ),
                Icon(icon, size: 28, color: const Color(0xFF172B3A)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF171717)),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Material(
                color: const Color(0xFFEEEEEE),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    _closeCategoryWindow();
                    if (!widget.openCategoryWindow) _toFocusNode.requestFocus();
                  },
                  child: const SizedBox(
                    height: 54,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('Куда едем?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF222222))),
                      SizedBox(width: 10),
                      Icon(Icons.arrow_circle_right, size: 24, color: Color(0xFF222222)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: places.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 74, color: Color(0xFFE8E8E8)),
                  itemBuilder: (context, index) {
                    final place = places[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                      leading: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(color: const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(14)),
                        child: Icon(
                          index == 2 ? Icons.storefront_rounded : Icons.location_on_rounded,
                          size: 26,
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                      title: Text(place.$1, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      subtitle: Text(place.$2, style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
                      trailing: Text(place.$3, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF6B7280))),
                      onTap: () {
                        _toController.text = '${place.$1}, ${place.$2}';
                        _closeCategoryWindow();
                        if (!widget.openCategoryWindow) _toFocusNode.requestFocus();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final markers = <Marker>[
      if (_fromPoint != null)
        Marker(
          point: _fromPoint!,
          width: 44,
          height: 44,
          child: const Icon(Icons.location_on_rounded, color: Color(0xFF159447), size: 38),
        ),
      if (_addStop && _stopPoint != null)
        Marker(
          point: _stopPoint!,
          width: 42,
          height: 42,
          child: const Icon(Icons.more_horiz, color: Color(0xFFB7791F), size: 34),
        ),
      if (_toPoint != null)
        Marker(
          point: _toPoint!,
          width: 46,
          height: 46,
          child: const Icon(Icons.location_on_rounded, color: Color(0xFFD83232), size: 42),
        ),
      for (final car in const [
        LatLng(42.3130, 69.5830),
        LatLng(42.3168, 69.5895),
        LatLng(42.3210, 69.5910),
        LatLng(42.3120, 69.5940),
      ])
        Marker(
          point: car,
          width: 30,
          height: 30,
          child: const Icon(Icons.local_taxi_rounded, color: Color(0xFFFFB800), size: 26),
        ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5FA),
      body: Stack(fit: StackFit.expand, children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(initialCenter: _shymkent, initialZoom: 14, onTap: _selectMapPoint),
          children: [
            TileLayer(
              urlTemplate: 'https://openstreetmap.org{z}/{x}/{y}.png',
              userAgentPackageName: 'kz.baketaxi.client',
            ),
            if (_route.isNotEmpty)
              PolylineLayer(polylines: [
                Polyline(
                  points: _route,
                  strokeWidth: 5.5,
                  color: const Color(0xFF1557D5),
                  borderStrokeWidth: 2,
                  borderColor: Colors.white,
                ),
              ]),
            MarkerLayer(markers: markers),
          ],
        ),

        if (!_showCategoryWindow) ...[
          Positioned(
            left: 16,
            bottom: size.height * 0.49,
            child: _mapBadge(
              icon: Icons.directions_car_rounded,
              topText: '2 мин',
              bottomText: 'Подача',
            ),
          ),
          Positioned(
            right: 16,
            top: size.height * 0.25,
            child: _mapBadge(
              icon: Icons.access_time_rounded,
              topText: '≈ ${_durationLabel ?? '8 мин'}',
              bottomText: _distanceLabel ?? '2.7 км',
            ),
          ),
        ],

        if (!_showCategoryWindow)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 4)),
                  ],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    const Icon(Icons.location_on_rounded, color: Color(0xFF159447), size: 24),
                    const SizedBox(width: 8),
                    const Text('Откуда:', style: TextStyle(fontSize: 13.5, color: Color(0xFF4B5563))),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _fromController,
                        focusNode: _fromFocusNode,
                        onSubmitted: (_) => _searchFrom(),
                        onChanged: (_) => setState(() {
                          _fromPoint = null;
                          _route = [];
                        }),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 30, height: 36),
                      onPressed: _searching ? null : _searchFrom,
                      icon: const Icon(Icons.chevron_right_rounded, size: 22, color: Color(0xFF111827)),
                    ),
                  ]),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  Row(children: [
                    const Icon(Icons.location_on_rounded, color: Color(0xFFD83232), size: 24),
                    const SizedBox(width: 8),
                    const Text('Куда:', style: TextStyle(fontSize: 13.5, color: Color(0xFF4B5563))),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _toController,
                        focusNode: _toFocusNode,
                        onSubmitted: (_) => _searchDestination(),
                        onChanged: (_) => setState(() {
                          _toPoint = null;
                          _route = [];
                        }),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 30, height: 36),
                      tooltip: 'Добавить остановку',
                      onPressed: () => setState(() => _addStop = !_addStop),
                      icon: Icon(_addStop ? Icons.remove_rounded : Icons.add_rounded, size: 26, color: Color(0xFF111827)),
                    ),
                  ]),
                  if (_addStop) ...[
                    const Divider(height: 1, color: Color(0xFFE5E7EB)),
                    _placeField(
                      Icons.more_horiz,
                      'Промежуточная остановка',
                      _stopController,
                      onSubmitted: (_) => _searchStop(),
                    ),
                  ],
                ]),
              ),
            ),
          ),

        if (!_showCategoryWindow) ...[
          Positioned(
            left: 16,
            bottom: size.height * 0.43 + 12,
            child: Material(
              color: Colors.white,
              elevation: 4,
              shape: const CircleBorder(),
              child: IconButton(
                onPressed: _locating ? null : _findMe,
                icon: const Icon(Icons.navigation_rounded, size: 24, color: Color(0xFF111827)),
                padding: const EdgeInsets.all(11),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: size.height * 0.43 + 12,
            child: Material(
              color: Colors.white,
              elevation: 4,
              shape: const CircleBorder(),
              child: IconButton(
                onPressed: () => _mapController.move(_fromPoint ?? _shymkent, 15),
                icon: const Icon(Icons.my_location_rounded, size: 24, color: Color(0xFF111827)),
                padding: const EdgeInsets.all(11),
              ),
            ),
          ),
        ],

        Positioned(
          left: 0,
          right: 0,
          top: _showCategoryWindow ? 0 : size.height * 0.56,
          bottom: 0,
          child: _showCategoryWindow
              ? _buildCategoryWindow()
              : Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -4))],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.directions_car_filled_rounded, size: 20, color: Color(0xFF111827)),
                            SizedBox(width: 8),
                            Text(
                              'Выберите класс авто',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF111827)),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 102,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _offerCard(0, 'Комфорт', 'Седан', Icons.directions_car_rounded),
                                _offerCard(1, 'Стандарт', 'Седан', Icons.directions_car_rounded),

