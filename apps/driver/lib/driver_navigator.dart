import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:jibek_shared/jibek_shared.dart';

const _navigatorPreferenceKey = 'driver_default_navigator';

const _navigatorNames = <String, String>{
  '2gis': '2ГИС (рекомендуется)',
  'yandex': 'Яндекс Навигатор',
  'google': 'Google Карты',
};

class DriverNavigatorPreferenceTile extends StatefulWidget {
  const DriverNavigatorPreferenceTile({super.key});

  @override
  State<DriverNavigatorPreferenceTile> createState() =>
      _DriverNavigatorPreferenceTileState();
}

class _DriverNavigatorPreferenceTileState
    extends State<DriverNavigatorPreferenceTile> {
  String _selected = '2gis';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _selected = preferences.getString(_navigatorPreferenceKey) ?? '2gis';
      _loading = false;
    });
  }

  Future<void> _savePreference(String? value) async {
    if (value == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_navigatorPreferenceKey, value);
    if (!mounted) return;
    setState(() => _selected = value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Навигатор по умолчанию: ${_navigatorNames[value]}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.navigation_rounded, color: Color(0xFF10243A)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Навигатор по умолчанию',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF10243A),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selected,
              isExpanded: true,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(),
              ),
              items: _navigatorNames.entries
                  .map((entry) => DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(entry.value),
                      ))
                  .toList(),
              onChanged: _loading ? null : _savePreference,
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      );
}

Future<void> openDriverNavigation(
  BuildContext context,
  JibekGeoPoint point,
) async {
  if (!point.isValid) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('В заказе указаны неверные координаты')),
    );
    return;
  }

  final preferences = await SharedPreferences.getInstance();
  final selected = preferences.getString(_navigatorPreferenceKey) ?? '2gis';
  final lat = point.latitude;
  final lon = point.longitude;

  late final Uri appUri;
  late final Uri fallbackUri;
  switch (selected) {
    case 'yandex':
      appUri = Uri.parse(
        'yandexnavi://build_route_on_map?lat_to=$lat&lon_to=$lon',
      );
      fallbackUri = Uri.parse(
        'https://yandex.kz/maps/?rtext=~$lat,$lon&rtt=auto',
      );
      break;
    case 'google':
      appUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=driving',
      );
      fallbackUri = appUri;
      break;
    case '2gis':
    default:
      appUri = Uri.parse(
        'dgis://2gis.ru/routeSearch/rsType/car/to/$lon,$lat',
      );
      fallbackUri = Uri.parse('https://2gis.kz');
      break;
  }

  try {
    final launched = await launchUrl(
      appUri,
      mode: LaunchMode.externalApplication,
    );
    if (launched) return;

    final fallbackLaunched = await launchUrl(
      fallbackUri,
      mode: LaunchMode.externalApplication,
    );
    if (!fallbackLaunched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть навигатор')),
      );
    }
  } catch (_) {
    try {
      final fallbackLaunched = await launchUrl(
        fallbackUri,
        mode: LaunchMode.externalApplication,
      );
      if (!fallbackLaunched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть навигатор')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть навигатор')),
        );
      }
    }
  }
}
