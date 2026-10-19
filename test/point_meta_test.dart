import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/features/dashboard/point_meta.dart';

void main() {
  test('variables del punto marcan caudal, nivel y total', () {
    final vars = PointVariables.fromJson([
      {'type_variable': 'CAUDAL', 'label': 'Caudal'},
      {'type_variable': 'NIVEL', 'label': 'Nivel'},
      {'type_variable': 'TOTALIZADO', 'label': 'Total'},
    ]);
    expect(vars.hasFlow, isTrue);
    expect(vars.hasLevel, isTrue);
    expect(vars.hasTotal, isTrue);
  });

  test('sin código ni dispositivo no hay ficha de cumplimiento', () {
    expect(DgaInfo.tryParse({'type_dga': 'SUBTERRANEO'}), isNull);
    expect(DgaInfo.tryParse({'send_dga': true}), isNull);
    final dga = DgaInfo.tryParse({
      'send_dga': true,
      'code_dga': 'OB-1603-392',
      'standard': 'MEDIO',
    });
    expect(dga?.agency, 'DGA');
    final sma = DgaInfo.tryParse({'code_dga': '7511', 'sma_device_id': '12'});
    expect(sma?.agency, 'SMA');
    expect(sma!.fields.map((f) => f.label), contains('Código UF'));
  });

  test('DGA, SMA o sin cumplimiento, con la regla del API', () {
    expect(
      complianceAgencyOf({'send_dga': true, 'code_dga': 'OB-1603-392'}),
      'DGA',
    );
    expect(
      complianceAgencyOf({
        'dga': {'send_dga': true, 'code_dga': 'ob-12'},
      }),
      'DGA',
    );
    expect(complianceAgencyOf({'code_dga': '7511-123'}), 'SMA');
    expect(complianceAgencyOf({'sma_device_id': '12180'}), 'SMA');
    expect(complianceAgencyOf({'title': 'P6'}), isNull);
    expect(complianceAgencyOf({'send_dga': true}), isNull);
    expect(
      complianceAgencyOf({
        'compliance_type': ['SMA'],
      }),
      'SMA',
    );
    expect(
      complianceAgencyOf({
        'compliance_type': ['DGA', 'SMA'],
      }),
      'DGA',
    );
  });

  test('detecta modelo Twin / Nettra / Novus', () {
    expect(loggerModelOf({'is_tdata': true}), 'Twin');
    expect(loggerModelOf({'provider': 'tdata'}), 'Twin');
    expect(loggerModelOf({'provider': 'nettra'}), 'Nettra');
    expect(loggerModelOf({'provider': 'thethings'}), 'Nettra');
    expect(loggerModelOf({'is_novus': true}), 'Novus');
    expect(loggerModelOf({'provider': 'tago'}), 'Novus');
    expect(loggerModelOf({'provider': 'novus'}), 'Novus');
    expect(loggerModelOf({'provider': 'tago', 'is_thethings': true}), 'Novus');
    expect(loggerModelOf({'provider': 'santiago'}), 'Santiago');
  });

  test('str_variable del esquema se mapea a su significado', () {
    final v = PointVariable.fromJson({
      'str_variable': 'ai1ActualValue',
      'label': 'Caudal',
      'type_variable': 'CAUDAL',
      'display_key': 'caudal',
    });
    expect(v.strVariable, 'ai1ActualValue');
    expect(v.schemaName, 'ai1ActualValue');
    expect(v.meaning, 'Caudal');
    expect(v.isFlow, isTrue);

    final info = LoggerInfo(variables: [v]);
    expect(info.schemeFields.single.label, 'ai1ActualValue');
    expect(info.schemeFields.single.value, 'Caudal');
    expect(
      PointVariable(type: 'TOTALIZADO', strVariable: 'totalizer1').simpleType,
      'Acumulado',
    );
    expect(PointVariable(type: 'NIVEL').simpleType, 'Nivel');
  });
}
