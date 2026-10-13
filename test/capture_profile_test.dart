import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/features/dashboard/capture_stage.dart';

void main() {
  test('lee la ficha d1-d5 y el caudal máximo de la config', () {
    final profile = CaptureProfile.fromConfig({
      'd1': '80.00',
      'd2': '55.50',
      'd3': '60.00',
      'd4': '4.00',
      'd5': 3,
      'max_flow_ls': '20.0',
    });

    expect(profile.depth, 80);
    expect(profile.pumpDepth, 55.5);
    expect(profile.sensorDepth, 60);
    expect(profile.ductInches, 4);
    expect(profile.flowmeterInches, 3);
    expect(profile.maxFlow, 20);
  });

  test('medidas ausentes, vacías o en cero quedan sin definir', () {
    final profile = CaptureProfile.fromConfig({
      'd1': '0.00',
      'd2': null,
      'd3': '',
      'd4': 'abc',
    });

    expect(profile.depth, isNull);
    expect(profile.pumpDepth, isNull);
    expect(profile.sensorDepth, isNull);
    expect(profile.ductInches, isNull);
    expect(profile.flowmeterInches, isNull);
    expect(profile.maxFlow, isNull);
  });
}
