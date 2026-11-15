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
  const PassengerMapPage({super.key, this.initialService = JibekServiceType.cityTaxi, this.initialDestination, this.initialNote});

  final JibekServiceType initialService;
  final String? initialDestination;
  final String? initialNote;

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
  int _selectedBottomTab = 0;
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _stopController = TextEditingController();
  bool _addStop = false;
  LatLng? _stopPoint;
  String _paymentMethod = 'Наличные';
  bool _childSeat = false;
  bool _needMovers = false;
  bool _boostSelected = false;
  int _intercitySeats = 1;
  String _intercityCity = 'Туркестан';
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
  int _tripRating = 5;
  JibekOrderRequest? _createdOrder;
  static const _apiUrl = String.fromEnvironment('JIBEK_API_URL');
  static const _devUserId = String.fromEnvironment('JIBEK_DEV_USER_ID');

  @override
  void initState() {
    super.initState();
    _service = widget.initialService;
    _fromController.text = 'ул. Тауке хана, 52';
    _toController.text = 'ТРЦ «Mega Shymkent»';
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
    // Адреса из утверждённого макета остаются начальными значениями.
    // Геолокация запускается отдельной кнопкой на карте.
  }

  void _onAddressFocusChanged() {
    final focused = _fromFocusNode.hasFocus || _toFocusNode.hasFocus;
    if (mounted && focused != _addressFieldFocused) setState(() => _addressFieldFocused = focused);
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
        addressText = [if (road != null) road, if (house != null) house, if (district != null) district, city]
            .map((part) => part.toString()).join(', ');
        if (addressText.isEmpty) addressText = reverseData['display_name']?.toString() ?? '';
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
        'https://router.project-osrm.org/route/v1/driving/'
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
        padding: const EdgeInsets.fromLTRB(42, 100, 42, 330),
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
    setState(() {
      switch (index) {
        case 0: _service = JibekServiceType.cityTaxi; _class = 'Комфорт'; break;
        case 1: _service = JibekServiceType.cityTaxi; _class = 'Стандарт'; break;
        case 2: _service = JibekServiceType.cityTaxi; _class = 'Бизнес'; break;
        case 3: _service = JibekServiceType.cityTaxi; _class = 'Минивэн'; break;
        case 4: _service = JibekServiceType.intercity; break;
        case 5: _service = JibekServiceType.freight; break;
        case 6: _service = JibekServiceType.parcel; break;
        case 7: _service = JibekServiceType.towTruck; break;
        case 8: _service = JibekServiceType.mobileTire; break;
      }
    });
  }

  int get _estimatedTaxiFare {
    switch (_class) {
      case 'Комфорт': return 1200;
      case 'Стандарт': return 1000;
      case 'Бизнес': return 1800;
      case 'Минивэн': return 2500;
      default: return 1000;
    }
  }

  String get _orderButtonLabel {
    if (_searching || _sendingOrder) return 'Подождите…';
    switch (_service) {
      case JibekServiceType.cityTaxi: return 'Заказать такси';
      case JibekServiceType.intercity: return 'Заказать межгород';
      case JibekServiceType.freight: return 'Заказать грузовой';
      case JibekServiceType.parcel: return 'Отправить посылку';
      case JibekServiceType.towTruck:
      case JibekServiceType.mobileTire: return 'Вызвать помощь';
    }
  }

  void _onBottomNavTap(int index) {
    setState(() => _selectedBottomTab = index);
    if (index == 1 || index == 3) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const PassengerProfilePage(),
      ));
    } else if (index == 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Чат с поддержкой будет подключён отдельно')),
      );
    }
  }

  Widget _offerCard(int index, String title, String subtitle, IconData icon, {double height = 142}) {
    final selected = _service == JibekServiceType.cityTaxi && _class == title;
    const prices = ['1 200 ₸', '1 000 ₸', '1 800 ₸', '2 500 ₸', 'По тарифу', 'По тарифу', 'По тарифу', 'По тарифу', 'По тарифу'];
    const assets = [
      'econom.png',
      'image_6681a04f.jpg',
      'business.png',
      'image_1e1f99f5.jpg',
      'cargo.png',
      'delivery.png',
      'tow.png',
      'tire.png',
      'intercity.png',
    ];
    return SizedBox(
      width: 118,
      child: GestureDetector(
        onTap: () => _selectOffer(index),
        child: Container(
          height: height,
          margin: const EdgeInsets.only(right: 7),
          padding: const EdgeInsets.fromLTRB(5, 5, 5, 6),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFFDF5) : const Color(0xFFF3F5FB),
            border: Border.all(
              color: selected ? const Color(0xFFFFC928) : const Color(0xFFE2E6F0),
              width: selected ? 2.5 : 1,
            ),
            borderRadius: BorderRadius.circular(19),
          ),
          child: Stack(children: [
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Expanded(
                child: Image.asset('assets/cars/${assets[index]}', fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(icon, size: 42, color: const Color(0xFF687386))),
              ),
              Text(title, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Color(0xFF111827))),
              const SizedBox(height: 2),
              Text(prices[index], textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF111827))),
            ]),
            if (selected) const Positioned(right: 0, top: 0, child: CircleAvatar(
              radius: 11, backgroundColor: Color(0xFFFFC928),
              child: Icon(Icons.check_rounded, size: 15, color: Color(0xFF172B3A)),
            )),
          ]),
        ),
      ),
    );
  }

  Widget _buildOfferOptions() {
    if (_service == JibekServiceType.cityTaxi) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: _metricTile(Icons.access_time_rounded, 'от 2 мин', 'Время подачи')),
          const SizedBox(width: 7),
          Expanded(child: _metricTile(Icons.route_rounded, _distanceLabel ?? '— км', 'Расстояние')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _metricTile(Icons.payments_rounded,
            '${_estimatedTaxiFare + (_boostSelected ? 250 : 0)} ₸', 'Итого к оплате')),
          const SizedBox(width: 7),
          Expanded(child: OutlinedButton.icon(
            onPressed: () => setState(() => _boostSelected = !_boostSelected),
            icon: Icon(_boostSelected ? Icons.check_circle : Icons.bolt_rounded),
            label: Text(_boostSelected ? 'Ускорение +250 ₸' : '+250 ₸ ускорить'),
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF9A6A00)),
          )),
        ]),
      ]);
    }
    if (_service == JibekServiceType.intercity) {
      return Row(children: [
        const Expanded(child: Text('Количество мест (1–4)',
          style: TextStyle(fontWeight: FontWeight.w800))),
        IconButton(
          onPressed: _intercitySeats > 1 ? () => setState(() => _intercitySeats--) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text('$_intercitySeats', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        IconButton(
          onPressed: _intercitySeats < 4 ? () => setState(() => _intercitySeats++) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ]);
    }
    if (_service == JibekServiceType.freight) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _needMovers,
        onChanged: (value) => setState(() => _needMovers = value),
        title: const Text('Нужны грузчики', style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: const Text('Дополнительная услуга к грузовому автомобилю'),
        activeColor: const Color(0xFFB58A16),
      );
    }
    final hint = _service == JibekServiceType.parcel
        ? 'Что передаём? От двери до двери'
        : _service == JibekServiceType.towTruck
            ? 'Тип авто и что случилось'
            : 'Тип автомобиля, размер колёс и проблема';
    return TextField(
      controller: _noteController,
      maxLines: 2,
      maxLength: 250,
      decoration: InputDecoration(
        labelText: hint,
        prefixIcon: const Icon(Icons.edit_note_rounded),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _passengerOrderPanel(JibekOrderRequest order) {
    final completed = order.status == JibekOrderStatus.completed;
    final cancelled = order.status == JibekOrderStatus.cancelled;
    final active = !completed && !cancelled;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: completed ? const Color(0xFFEAF7EE) : const Color(0xFFF3F6FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: completed ? const Color(0xFFB9E2C5) : const Color(0xFFE0E6EF)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(completed ? Icons.check_circle_rounded : cancelled ? Icons.cancel_rounded : Icons.local_taxi_rounded,
            color: completed ? const Color(0xFF21864B) : const Color(0xFF173B6C), size: 22),
          const SizedBox(width: 7),
          Expanded(child: Text(completed ? 'Поездка завершена!' : cancelled ? 'Заказ отменён' : 'Вы в пути / заказ активен',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
          IconButton(visualDensity: VisualDensity.compact, tooltip: 'Обновить статус',
            onPressed: _refreshingOrder ? null : _refreshOrder,
            icon: _refreshingOrder ? const SizedBox(width: 17,height: 17,child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded)),
        ]),
        Text('Откуда: ${order.pickup.address ?? 'Точка на карте'}', maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11)),
        Text('Куда: ${order.destination.address ?? 'Точка на карте'}', maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 7),
        if (completed) ...[
          Text('${order.priceKzt} ₸', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: Color(0xFF21864B))),
          const Text('Чек и детали поездки доступны в истории заказов.', style: TextStyle(fontSize: 11, color: Color(0xFF687386))),
          const SizedBox(height: 7),
          const Text('Оцените поездку', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          Row(children: List.generate(5, (index) => IconButton(
            visualDensity: VisualDensity.compact, padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 31, minHeight: 31),
            onPressed: () => setState(() => _tripRating = index + 1),
            icon: Icon(index < _tripRating ? Icons.star_rounded : Icons.star_outline_rounded,
              color: const Color(0xFFFFB800), size: 25),
          ))),
        ] else if (active) ...[
          const Text('Водитель / автомобиль появятся после назначения в системе.', style: TextStyle(fontSize: 11, color: Color(0xFF687386))),
          const SizedBox(height: 6),
          Text('${order.priceKzt} ₸', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () => _message('Чат и звонок станут доступны после подключения связи с водителем.'),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16), label: const Text('Чат', style: TextStyle(fontSize: 11)))),
            const SizedBox(width: 6),
            Expanded(child: OutlinedButton.icon(
              onPressed: _cancellingOrder || !_canCancelOrder(order.status) ? null : _cancelOrder,
              icon: const Icon(Icons.close_rounded, size: 16), label: const Text('Отменить', style: TextStyle(fontSize: 11)))),
          ]),
        ],
      ]),
    );
  }

  Widget _quickTile(BuildContext context, String title, String subtitle, IconData icon, Color tint, VoidCallback onTap, {double height = 86}) =>
      Material(
        color: tint,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: SizedBox(
            height: height,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 21, color: const Color(0xFF172B3A)),
              const SizedBox(height: 6),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF172B3A))),
              const SizedBox(height: 2),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 8, color: Color(0xFF172B3A))),
            ]),
          ),
        ),
      );

  Widget _compactSummary(IconData icon, String value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: const Color(0xFF687386)),
      const SizedBox(width: 3),
      Flexible(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
    ],
  );

  Widget _metricTile(IconData icon, String value, String label,
      {double height = 78, bool showInfo = false}) => Container(
    height: height,
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
    decoration: BoxDecoration(color: const Color(0xFFF1F3FA), borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE4E8F2))),
    child: Row(children: [
      Icon(icon, color: const Color(0xFF172B3A), size: 18),
      const SizedBox(width: 6),
      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12))),
          if (showInfo) const Icon(Icons.info_outline_rounded, size: 17, color: Color(0xFF173B6C)),
        ]),
        Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 9, color: Color(0xFF172033))),
      ])),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final markers = <Marker>[
      if (_fromPoint != null)
        Marker(point: _fromPoint!, width: 42, height: 42,
          child: const Icon(Icons.my_location, color: Color(0xFF126B45), size: 32)),
      if (_addStop && _stopPoint != null)
        Marker(point: _stopPoint!, width: 42, height: 42,
          child: const Icon(Icons.more_horiz, color: Color(0xFFB7791F), size: 34)),
      if (_toPoint != null)
        Marker(point: _toPoint!, width: 46, height: 46,
          child: const Icon(Icons.location_on, color: Color(0xFFC62828), size: 42)),
      for (final car in const [
        LatLng(42.3190, 69.5790), LatLng(42.3090, 69.5920),
        LatLng(42.3250, 69.6000), LatLng(42.3060, 69.5700),
      ])
        Marker(point: car, width: 27, height: 27,
          child: const Icon(Icons.local_taxi_rounded, color: Color(0xFFFFB800), size: 25)),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5FA),
      body: Stack(fit: StackFit.expand, children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(initialCenter: _shymkent, initialZoom: 13, onTap: _selectMapPoint),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'kz.baketaxi.client'),
            if (_route.isNotEmpty)
              PolylineLayer(polylines: [Polyline(points: _route, strokeWidth: 5,
                color: const Color(0xFF1557D5), borderStrokeWidth: 1.5, borderColor: Colors.white)]),
            MarkerLayer(markers: markers),
            const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors')]),
          ],
        ),

        // Верхняя адресная плашка — остаётся поверх карты и не прокручивается.
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 3))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const Icon(Icons.location_on_rounded, color: Color(0xFF159447), size: 27),
                  const SizedBox(width: 8),
                  const Text('Откуда:', style: TextStyle(fontSize: 14, color: Color(0xFF172033))),
                  const SizedBox(width: 7),
                  Expanded(child: TextField(
                    controller: _fromController, focusNode: _fromFocusNode,
                    onSubmitted: (_) => _searchFrom(),
                    onChanged: (_) => setState(() { _fromPoint = null; _route = []; }),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF172033)),
                    decoration: const InputDecoration(
                      border: InputBorder.none, isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 13),
                    ),
                  )),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 32, height: 38),
                    onPressed: _searching ? null : _searchFrom,
                    icon: const Icon(Icons.chevron_right_rounded, size: 21, color: Color(0xFF172033)),
                  ),
                ]),
                const Divider(height: 1, color: Color(0xFFE5E8EF)),
                Row(children: [
                  const Icon(Icons.location_on_rounded, color: Color(0xFFD83232), size: 27),
                  const SizedBox(width: 8),
                  const Text('Куда:', style: TextStyle(fontSize: 14, color: Color(0xFF172033))),
                  const SizedBox(width: 7),
                  Expanded(child: TextField(
                    controller: _toController, focusNode: _toFocusNode,
                    onSubmitted: (_) => _searchDestination(),
                    onChanged: (_) => setState(() { _toPoint = null; _route = []; }),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF172033)),
                    decoration: const InputDecoration(
                      border: InputBorder.none, isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 13),
                    ),
                  )),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 32, height: 38),
                    tooltip: 'Добавить остановку',
                    onPressed: () => setState(() => _addStop = !_addStop),
                    icon: const Icon(Icons.add_rounded, size: 29, color: Color(0xFF172033)),
                  ),
                ]),
                if (_addStop) _placeField(Icons.more_horiz, 'Промежуточная остановка', _stopController,
                  onSubmitted: (_) => _searchStop()),
              ]),
            ),
          ),
        ),

        // Круглые кнопки карты располагаются непосредственно над панелью заказа.
        Positioned(
          left: 16, bottom: size.height * .405,
          child: Material(
            color: Colors.white, elevation: 5, shape: const CircleBorder(),
            child: IconButton(
              onPressed: _locating ? null : _findMe,
              icon: const Icon(Icons.navigation_rounded, size: 27, color: Color(0xFF172033)),
              iconSize: 46, padding: const EdgeInsets.all(13),
            ),
          ),
        ),
        Positioned(
          right: 16, bottom: size.height * .405,
          child: Material(
            color: Colors.white, elevation: 5, shape: const CircleBorder(),
            child: IconButton(
              onPressed: () => _mapController.move(_fromPoint ?? _shymkent, 15),
              icon: const Icon(Icons.my_location_rounded, size: 27, color: Color(0xFF172033)),
              iconSize: 46, padding: const EdgeInsets.all(13),
            ),
          ),
        ),

        // Заказная панель и нижние четыре блока закреплены внизу экрана.
        Positioned(
          left: 0, right: 0, top: size.height * .60, bottom: 0,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, -4))],
            ),
            child: SafeArea(
              top: false,
              child: LayoutBuilder(builder: (context, constraints) {
                final compact = constraints.maxHeight < 500;
                final cardHeight = compact ? 70.0 : 92.0;
                final metricHeight = compact ? 48.0 : 58.0;
                final buttonHeight = compact ? 46.0 : 52.0;
                final menuHeight = compact ? 54.0 : 64.0;
                return Padding(
                  padding: const EdgeInsets.only(top: 5, bottom: 2),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(children: const [
                          Icon(Icons.directions_car_filled_rounded, size: 21, color: Color(0xFF172033)),
                          SizedBox(width: 9),
                          Text('Выберите класс авто',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF172033))),
                        ]),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: SizedBox(
                          height: cardHeight,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(right: 2),
                            children: [
                              _offerCard(0, 'Комфорт', 'Седан', Icons.directions_car_rounded, height: cardHeight),
                              _offerCard(1, 'Стандарт', 'Седан', Icons.directions_car_rounded, height: cardHeight),
                              _offerCard(2, 'Бизнес', 'Седан', Icons.directions_car_filled_rounded, height: cardHeight),
                              _offerCard(3, 'Минивэн', '6–7 мест', Icons.airport_shuttle_rounded, height: cardHeight),
                              _offerCard(5, 'Грузовой', 'Грузовик', Icons.local_shipping_rounded, height: cardHeight),
                              _offerCard(6, 'Доставка', 'Посылка', Icons.inventory_2_rounded, height: cardHeight),
                              _offerCard(7, 'Эвакуатор', 'Помощь', Icons.car_crash_rounded, height: cardHeight),
                              _offerCard(8, 'Шиномонтаж', 'Колесо и домкрат', Icons.tire_repair_rounded, height: cardHeight),
                              _offerCard(4, 'Межгород', 'Поездки', Icons.route_rounded, height: cardHeight),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: SizedBox(
                          height: metricHeight,
                          child: Row(children: [
                            Expanded(child: _metricTile(Icons.access_time_rounded, '~ 8 мин', 'Время подачи', height: metricHeight)),
                            const SizedBox(width: 5),
                            Expanded(child: _metricTile(Icons.route_rounded, _distanceLabel ?? '2.7 км', 'Расстояние', height: metricHeight)),
                            const SizedBox(width: 5),
                            Expanded(child: _metricTile(Icons.credit_card_rounded,
                              '${_estimatedTaxiFare + (_boostSelected ? 250 : 0)} ₸', 'Итого к оплате',
                              height: metricHeight, showInfo: true)),
                          ]),
                        ),
                      ),
                      if (_createdOrder != null) ...[
                        const SizedBox(height: 6),
                        SizedBox(
                          height: compact ? 48 : 58,
                          child: ClipRect(child: _passengerOrderPanel(_createdOrder!)),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: SizedBox(
                          height: buttonHeight, width: double.infinity,
                          child: FilledButton(
                            onPressed: (_searching || _sendingOrder) ? null : () {
                              if (_toPoint == null) {
                                if (_toController.text.trim().isEmpty) {
                                  _message('Укажите адрес назначения');
                                } else { _searchDestination(); }
                              } else if (_fromPoint == null) {
                                _searchFrom();
                              } else if (_route.isEmpty) {
                                _buildRoute();
                              } else {
                                _submitOrder();
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFFC400),
                              foregroundColor: const Color(0xFF101827),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              const Icon(Icons.directions_car_filled_rounded, size: 23, color: Color(0xFF101827)),
                              const SizedBox(width: 12),
                              Text(_orderButtonLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(children: [
                            Expanded(child: _quickTile(context, 'Доставка', 'Посылки и товары', Icons.inventory_2_rounded,
                              const Color(0xFFE9E3FF), () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => const PassengerMapPage(initialService: JibekServiceType.parcel))), height: menuHeight)),
                            const SizedBox(width: 4),
                            Expanded(child: _quickTile(context, 'Услуги', 'Эвакуатор, мастер…', Icons.build_rounded,
                              const Color(0xFFD9F5EC), () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => const BakeServicesPage())), height: menuHeight)),
                            const SizedBox(width: 4),
                            Expanded(child: _quickTile(context, 'Межгород', 'Поездки по РК', Icons.route_rounded,
                              const Color(0xFFDCEBFF), () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => const IntercityPage())), height: menuHeight)),
                            const SizedBox(width: 4),
                            Expanded(child: _quickTile(context, 'Помощь', 'Поддержка 24/7', Icons.headset_mic_rounded,
                              const Color(0xFFFFE3D4), () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => const BakeHelpPage())), height: menuHeight)),
                          ]),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _showPreferences() async {
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true,
      builder: (context) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Пожелания к заказу', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          TextField(controller: _noteController, maxLines: 2, decoration: const InputDecoration(labelText: 'Комментарий водителю')),
          const SizedBox(height: 8),
          CheckboxListTile(value: _childSeat, onChanged: (v) => setState(() => _childSeat = v ?? false), title: const Text('Детское кресло'), contentPadding: EdgeInsets.zero),
          CheckboxListTile(value: _needMovers, onChanged: (v) => setState(() => _needMovers = v ?? false), title: const Text('Нужны грузчики'), contentPadding: EdgeInsets.zero),
          Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Готово'))),
        ]),
      )),
    );
  }

  Future<void> _submitOrder() async {
    final requiresDetails = _service == JibekServiceType.parcel ||
        _service == JibekServiceType.towTruck ||
        _service == JibekServiceType.mobileTire;
    if (requiresDetails && _noteController.text.trim().isEmpty) {
      _message(_service == JibekServiceType.parcel
          ? 'Опишите посылку и что нужно доставить'
           : _service == JibekServiceType.freight
              ? 'Опишите груз, габариты и адрес доставки'
              : _service == JibekServiceType.towTruck
              ? 'Укажите автомобиль и характер поломки'
              : 'Укажите размер колёс и проблему');
      return;
    }
    if (_addStop && _stopPoint == null) {
      _message('Сначала найдите промежуточную остановку');
      return;
    }
    if (_fromPoint == null || _toPoint == null || _route.isEmpty) {
      _message('Сначала постройте маршрут'); return;
    }
    if (_apiUrl.isEmpty || _devUserId.isEmpty) {
      _message('Отправка пока закрыта: сервер и тестовый доступ не настроены'); return;
    }
    setState(() => _sendingOrder = true);
    final repository = DevJibekApiRepository(baseUrl: _apiUrl, devUserIdProvider: () async => _devUserId);
    final orderNote = [
      _noteController.text.trim(),
      if (_childSeat) 'Детское кресло',
      if (_service == JibekServiceType.freight) 'Грузовой заказ',
      if (_service == JibekServiceType.intercity) 'Межгород: $_intercityCity; мест: $_intercitySeats',
      if (_needMovers) 'Нужны грузчики',
      if (_boostSelected) 'Приоритет +250 ₸',
      'Оплата: $_paymentMethod',
    ].where((item) => item.isNotEmpty).join('; ');
    try {
      final draft = JibekOrderRequest(
        id: 'local-draft', service: _service,
        pickup: JibekGeoPoint(latitude: _fromPoint!.latitude, longitude: _fromPoint!.longitude, address: _fromController.text),
        destination: JibekGeoPoint(latitude: _toPoint!.latitude, longitude: _toPoint!.longitude, address: _toController.text),
        stops: _addStop && _stopPoint != null
            ? [JibekGeoPoint(latitude: _stopPoint!.latitude, longitude: _stopPoint!.longitude, address: _stopController.text)]
            : const [],
        createdAt: DateTime.now(),
        vehicleClass: _service == JibekServiceType.cityTaxi ? _class : null,
        note: orderNote.isEmpty ? null : orderNote,
        priceKzt: _service == JibekServiceType.cityTaxi ? _estimatedTaxiFare + (_boostSelected ? 250 : 0) : 250,
        boostCount: _boostSelected ? 1 : 0,
      );
      final validation = draft.validate();
      if (validation != null) { _message(validation); return; }
      final created = await repository.createOrder(draft);
      if (!mounted) return;
      setState(() => _createdOrder = created);
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('jibek_passenger_active_order_id', created.id);
      await _saveOrderToHistory(created);
      _message('Заявка создана. Номер: ' + created.id);
    } on JibekApiException catch (e) {
      _message('Не удалось отправить заявку: ' + e.message);
    } catch (_) { _message('Нет связи с сервером. Повторите позже.'); }
    finally { repository.close(); if (mounted) setState(() { _sendingOrder = false; _searching = false; }); }
  }
  Future<void> _restoreSavedOrder() async {
    if (_apiUrl.isEmpty || _devUserId.isEmpty) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      final orderId = preferences.getString('jibek_passenger_active_order_id');
      if (orderId == null || orderId.isEmpty) return;
      final repository = _orderRepository();
      try {
        final order = await repository.getOrder(orderId: orderId);
        if (!mounted) return;
        setState(() => _createdOrder = order);
        await _saveOrderState(order);
      } on JibekApiException catch (error) {
        if (error.statusCode == 404 || error.statusCode == 403) {
          await preferences.remove('jibek_passenger_active_order_id');
        } else {
          _message('Не удалось восстановить заявку: ${error.message}');
        }
      } finally {
        repository.close();
      }
    } catch (_) {
      _message('Не удалось восстановить сохранённую заявку');
    }
  }

  Future<void> _saveOrderToHistory(JibekOrderRequest order) async {
    final preferences = await SharedPreferences.getInstance();
    final history = preferences.getStringList('bake_taxi_order_history') ?? <String>[];
    history.removeWhere((entry) {
      try {
        return (jsonDecode(entry) as Map)['id'] == order.id;
      } catch (_) {
        return false;
      }
    });
    history.insert(0, jsonEncode(order.toJson()));
    await preferences.setStringList(
      'bake_taxi_order_history',
      history.take(20).toList(),
    );
  }

  Future<void> _saveOrderState(JibekOrderRequest order) async {
    await _saveOrderToHistory(order);
    final isTerminal = order.status == JibekOrderStatus.completed ||
        order.status == JibekOrderStatus.cancelled;
    if (!isTerminal) return;
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getString('jibek_passenger_active_order_id') == order.id) {
      await preferences.remove('jibek_passenger_active_order_id');
    }
  }

  String _statusLabel(JibekOrderStatus status) => switch (status) {
        JibekOrderStatus.searching => 'Ищем водителя',
        JibekOrderStatus.accepted => 'Водитель принял заказ',
        JibekOrderStatus.driverArriving => 'Водитель едет к вам',
        JibekOrderStatus.inProgress => 'Поездка началась',
        JibekOrderStatus.completed => 'Поездка завершена',
        JibekOrderStatus.cancelled => 'Заказ отменён',
        JibekOrderStatus.draft => 'Черновик',
      };

  bool _canCancelOrder(JibekOrderStatus status) =>
      status == JibekOrderStatus.searching ||
      status == JibekOrderStatus.accepted ||
      status == JibekOrderStatus.driverArriving;

  DevJibekApiRepository _orderRepository() => DevJibekApiRepository(
        baseUrl: _apiUrl,
        devUserIdProvider: () async => _devUserId,
      );

  Future<void> _boostOrder() async {
    final order = _createdOrder;
    if (order == null || order.status != JibekOrderStatus.searching || _apiUrl.isEmpty || _devUserId.isEmpty) return;
    setState(() => _refreshingOrder = true);
    final repository = _orderRepository();
    try {
      final updated = await repository.boostOrder(orderId: order.id, amountKzt: 250);
      if (!mounted) return;
      setState(() => _createdOrder = updated);
      await _saveOrderState(updated);
      _message('Цена увеличена до ${updated.priceKzt} ₸');
    } on JibekApiException catch (e) {
      _message('Не удалось повысить цену: ${e.message}');
    } catch (_) { _message('Нет связи с сервером. Цена не изменена.'); }
    finally { repository.close(); if (mounted) setState(() => _refreshingOrder = false); }
  }

  Future<void> _refreshOrder() async {
    final order = _createdOrder;
    if (order == null || _apiUrl.isEmpty || _devUserId.isEmpty) return;
    setState(() => _refreshingOrder = true);
    final repository = _orderRepository();
    try {
      final updated = await repository.getOrder(orderId: order.id);
      if (!mounted) return;
      setState(() => _createdOrder = updated);
      await _saveOrderState(updated);
      _message('Статус обновлён: ${_statusLabel(updated.status)}');
    } on JibekApiException catch (e) {
      _message('Не удалось обновить статус: ${e.message}');
    } catch (_) {
      _message('Нет связи с сервером. Повторите позже.');
    } finally {
      repository.close();
      if (mounted) setState(() => _refreshingOrder = false);
    }
  }

  Future<void> _cancelOrder() async {
    final order = _createdOrder;
    if (order == null || !_canCancelOrder(order.status)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отменить заявку?'),
        content: const Text('Водитель больше не сможет принять этот заказ.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Оставить'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отменить заказ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cancellingOrder = true);
    final repository = _orderRepository();
    try {
      final updated = await repository.updateOrderStatus(
        orderId: order.id,
        status: JibekOrderStatus.cancelled,
      );
      if (!mounted) return;
      setState(() => _createdOrder = updated);
      await _saveOrderState(updated);
      _message('Заявка отменена');
    } on JibekApiException catch (e) {
      _message('Не удалось отменить заявку: ${e.message}');
    } catch (_) {
      _message('Нет связи с сервером. Повторите позже.');
    } finally {
      repository.close();
      if (mounted) setState(() => _cancellingOrder = false);
    }
  }

  Future<void> _searchFrom() async {
    final query = _fromController.text.trim();
    if (query.isEmpty) {
      await _findMe();
      return;
    }
    setState(() => _searching = true);
    try {
      final result = await _geocode('$query, Шымкент, Казахстан');
      if (result == null) {
        _message('Адрес отправления не найден');
        return;
      }
      setState(() => _fromPoint = result.point);
      _mapController.move(result.point, 14);
      if (_toPoint != null) await _buildRoute();
    } catch (e) {
      _message('Ошибка поиска адреса: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Widget _placeField(
    IconData icon,
    String hint,
    TextEditingController controller, {
    required ValueChanged<String> onSubmitted,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF10243A)),
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
        suffixIcon: controller.text.isEmpty ? null : IconButton(
          tooltip: 'Очистить адрес',
          icon: const Icon(Icons.close_rounded),
          onPressed: () { controller.clear(); onChanged?.call(''); },
        ),
      ),
    );
  }
}

class BakeServicesPage extends StatelessWidget {
  const BakeServicesPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F6F9),
    appBar: AppBar(title: const Text('Услуги'), backgroundColor: Colors.white, foregroundColor: const Color(0xFF172B3A)),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Помощь на дороге и для дома', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 12),
      _service('Эвакуатор', Icons.car_crash_rounded, JibekServiceType.towTruck, context),
      _service('Шиномонтаж', Icons.tire_repair_rounded, JibekServiceType.mobileTire, context, asset: 'assets/cars/tire.png'),
      _service('Автоэлектрик', Icons.electrical_services_rounded, JibekServiceType.mobileTire, context),
      _service('Сантехник', Icons.plumbing_rounded, JibekServiceType.mobileTire, context),
      _service('Электрик', Icons.bolt_rounded, JibekServiceType.mobileTire, context),
    ]),
  );
  Widget _service(String title, IconData icon, JibekServiceType type, BuildContext context, {String? asset}) => Card(
    color: Colors.white, elevation: 0, margin: const EdgeInsets.only(bottom: 9),
    child: ListTile(leading: asset == null
        ? CircleAvatar(backgroundColor: const Color(0xFFFFF0C2), child: Icon(icon, color: const Color(0xFF172B3A)))
        : SizedBox(width: 56, height: 56, child: Image.asset(asset, fit: BoxFit.contain)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PassengerMapPage(initialService: type, initialNote: title)))),
  );
}

class BakeHelpPage extends StatelessWidget {
  const BakeHelpPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F6F9),
    appBar: AppBar(title: const Text('Помощь 24/7'), backgroundColor: Colors.white, foregroundColor: const Color(0xFF172B3A)),
    body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.support_agent_rounded, size: 64, color: Color(0xFF172B3A)),
      const SizedBox(height: 12),
      const Text('Поддержка Bake Taxi', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      const Text('Служба поддержки работает круглосуточно. Связь с оператором будет доступна после подключения канала поддержки.',
        textAlign: TextAlign.center),
      const SizedBox(height: 18),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Канал поддержки ещё не подключён'))),
        icon: const Icon(Icons.headset_mic_rounded), label: const Text('Связаться с поддержкой'))),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Экстренный вызов SOS пока не подключён'))),
        icon: const Icon(Icons.sos_rounded), label: const Text('SOS'))),
    ]))),
  );
}

