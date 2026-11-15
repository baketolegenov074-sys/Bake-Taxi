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
