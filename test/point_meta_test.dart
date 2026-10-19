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

  test('sin send_dga ni código no hay ficha DGA', () {
    expect(DgaInfo.tryParse({'type_dga': 'SUBTERRANEO'}), isNull);
    expect(
      DgaInfo.tryParse({
        'send_dga': true,
        'code_dga': 'X1',
        'standard': 'MEDIO',
      }),
      isNotNull,
    );
  });

  test('si no es DGA el punto es SMA', () {
    expect(complianceAgencyOf({'send_dga': true, 'code_dga': 'X1'}), 'DGA');
    expect(
      complianceAgencyOf({
        'dga': {'send_dga': true, 'code_dga': 'X1'},
      }),
      'DGA',
    );
    expect(complianceAgencyOf({'title': 'P6'}), 'SMA');
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
