import 'package:flutter_test/flutter_test.dart';
import 'package:bake_taxi_shared/bake_taxi_shared.dart';

void main() {
  group('BakeTaxiOrderRequest', () {
    final pickup = BakeTaxiGeoPoint(
      latitude: 42.3154,
      longitude: 69.5869,
      address: 'Шымкент',
    );
    final destination = BakeTaxiGeoPoint(
      latitude: 42.32,
      longitude: 69.60,
      address: 'Шымкент, центр',
    );

    test('serializes and restores an order', () {
      final order = BakeTaxiOrderRequest(
        id: 'test-order-1',
        service: BakeTaxiServiceType.cityTaxi,
        pickup: pickup,
        destination: destination,
        createdAt: DateTime.utc(2026, 11, 12),
        vehicleClass: 'Эконом',
      );

      final restored = BakeTaxiOrderRequest.fromJson(order.toJson());

      expect(restored.id, order.id);
      expect(restored.service, BakeTaxiServiceType.cityTaxi);
      expect(restored.pickup.latitude, pickup.latitude);
      expect(restored.status, BakeTaxiOrderStatus.draft);
      expect(restored.validate(), isNull);
    });

    test('rejects identical pickup and destination', () {
      final order = BakeTaxiOrderRequest(
        id: 'test-order-2',
        service: BakeTaxiServiceType.intercity,
        pickup: pickup,
        destination: pickup,
        createdAt: DateTime.utc(2026, 11, 12),
      );

      expect(order.validate(), contains('совпадают'));
    });

    test('requires service details for parcel, tow truck and mobile tire', () {
      for (final service in [
        BakeTaxiServiceType.parcel,
        BakeTaxiServiceType.towTruck,
        BakeTaxiServiceType.mobileTire,
      ]) {
        final order = BakeTaxiOrderRequest(
          id: 'details-required',
          service: service,
          pickup: pickup,
          destination: destination,
          createdAt: DateTime.utc(2026, 11, 12),
        );
        expect(order.validate(), isNotNull);
      }
    });

    test('accepts service details for parcel, tow truck and mobile tire', () {
      for (final service in [
        BakeTaxiServiceType.parcel,
        BakeTaxiServiceType.towTruck,
        BakeTaxiServiceType.mobileTire,
      ]) {
        final order = BakeTaxiOrderRequest(
          id: 'details-present',
          service: service,
          pickup: pickup,
          destination: destination,
          createdAt: DateTime.utc(2026, 11, 12),
          note: 'Подробности заявки',
        );
        expect(order.validate(), isNull);
      }
    });

    test('requires vehicle class for city taxi', () {
      final order = BakeTaxiOrderRequest(
        id: 'test-order-3',
        service: BakeTaxiServiceType.cityTaxi,
        pickup: pickup,
        destination: destination,
        createdAt: DateTime.utc(2026, 11, 12),
      );

      expect(order.validate(), contains('класс автомобиля'));
    });
  });
}
