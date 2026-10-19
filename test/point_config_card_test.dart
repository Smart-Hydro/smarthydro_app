import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarthydro_app/core/api/smarthydro_api.dart';
import 'package:smarthydro_app/features/dashboard/widgets/point_config_card.dart';

void main() {
  test('el proveedor sigue el handler del summary', () {
    expect(configProviderKey({'provider': 'thethings'}), 'nettra');
    expect(configProviderKey({'provider': 'tdata'}), 'twin');
    expect(configProviderKey({'provider': 'tago'}), 'novus');
    expect(configProviderKey({'is_novus': true}), 'novus');
    expect(configProviderKey({'title': 'P6'}), 'none');
  });

  test('el proyecto acepta id anidado', () {
    expect(configProjectId(9), 9);
    expect(configProjectId({'id': 4, 'name': 'Fundo'}), 4);
    expect(configProjectId('12'), 12);
    expect(configProjectId(null), isNull);
  });

  test('el select sale de los puntos, sin repetir', () {
    final scoped = configProjectsOf([
      {
        'id': 1,
        'project': {'id': 9, 'name': 'Fundo'},
      },
      {'id': 2, 'project_id': 9, 'project_name': 'Fundo'},
      {
        'id': 3,
        'project': {'id': 4, 'name': 'Valle'},
      },
    ]);
    expect(scoped.map((project) => project['id']), [9, 4]);
    expect(scoped.map((project) => project['name']), ['Fundo', 'Valle']);
  });

  test('el catálogo se recorta a los puntos de la cuenta', () {
    final scoped = configProjectsFromCatalog(
      [
        {'id': 9, 'name': 'Fundo'},
        {'id': 4, 'name': 'Valle'},
        {'id': 80, 'name': 'Otro'},
      ],
      [
        {'project_name': 'Fundo'},
        {
          'project': {'id': 4, 'name': 'Valle'},
        },
      ],
    );
    expect(scoped.map((project) => project['name']), ['Fundo', 'Valle']);
    expect(scoped.any((project) => project['name'] == 'Otro'), isFalse);
  });

  test('el catálogo de esquemas se recorta a mis puntos', () {
    final scoped = configSchemesOf(
      [
        {
          'id': 2,
          'name': 'Esquema Fundo',
          'points_catchment': [1, 2],
        },
        {
          'id': 9,
          'name': 'Ajeno',
          'points_catchment': [80],
        },
      ],
      const [1, 2],
    );
    expect(scoped.map((scheme) => scheme['name']), ['Esquema Fundo']);
    expect(configSchemePointIds(scoped.single), [1, 2]);
  });

  test('sin indicios no se usa el catálogo entero', () {
    expect(
      configProjectsFromCatalog(
        [
          {'id': 80, 'name': 'Otro'},
        ],
        [
          {'id': 1, 'title': 'P6'},
        ],
      ),
      isEmpty,
    );
  });

  test('DGA y física se leen del summary', () {
    final point = {
      'send_dga': true,
      'code_dga': 'OB-1603-392',
      'dga': {'flow_granted_dga': 12.5, 'shac': 'SHAC-1'},
      'config': {'d1': 80, 'nivel_offset': 1.2},
      'variables': [
        {'type_variable': 'CAUDAL', 'str_variable': 'ai1'},
      ],
    };
    expect(dgaRowsOf(point).first['code_dga'], 'OB-1603-392');
    expect(dgaRowsOf(point).first['flow_granted_dga'], 12.5);
    expect(configPayloadOf(point)?['d1'], 80);
    expect(variableMapsOf(point).single['str_variable'], 'ai1');
  });

  testWidgets('abre con los valores del punto, sin esperar al API', (
    tester,
  ) async {
    await tester.pumpWidget(
      _card(point: _samplePoint(), initialPanel: 'telemetry'),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Nettra'), findsOneWidget);

    await tester.tap(find.text('Punto'));
    await tester.pump();
    expect(_fieldText(tester, 'Nombre'), 'P6');
    expect(find.text('Fundo'), findsOneWidget);
    expect(
      find.text(
        'Solo los proyectos donde ya tienes puntos. Ahí puedes crear más.',
      ),
      findsOneWidget,
    );
    expect(_fieldText(tester, 'Frecuencia (min)'), '15');
    expect(_fieldText(tester, 'Latitud'), '-33.4');
    expect(_fieldText(tester, 'Longitud'), '-70.6');

    await tester.tap(find.text('Cumplimiento'));
    await tester.pump();
    expect(find.text('Cumplimiento DGA'), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-config-code')), findsOneWidget);
    expect(_fieldText(tester, 'Código de obra'), 'OB-1603-392');
    expect(_fieldText(tester, 'Caudal otorgado (L/s)'), '12.5');

    await tester.tap(find.text('Física'));
    await tester.pump();
    expect(_fieldText(tester, 'Profundidad (m)'), '80');
    expect(_fieldText(tester, 'Bomba (m)'), '60');

    await tester.tap(find.text('Esquema'));
    await tester.pump();
    expect(find.text('Nuevo para este punto'), findsOneWidget);
    expect(find.text('Elegir existente'), findsOneWidget);
    expect(_fieldText(tester, 'Código'), 'ai1');
    expect(_fieldText(tester, 'Etiqueta'), 'Caudal pozo');
  });

  testWidgets('las lecturas del servidor parten juntas', (tester) async {
    final api = _SlowApi();
    await tester.pumpWidget(
      _card(point: _samplePoint(), token: 't', api: api, initialPanel: 'point'),
    );
    await tester.pump();
    expect(find.text('Configurar punto'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 120));
    expect(api.started.containsKey('projects'), isFalse);
    expect(api.started.length, 4);
    final first = api.started.values.reduce((a, b) => a.isBefore(b) ? a : b);
    for (final time in api.started.values) {
      expect(time.difference(first).inMilliseconds, lessThan(20));
    }
    expect(find.text('Fundo'), findsOneWidget);
    await tester.tap(find.text('Física'));
    await tester.pump();
    expect(_fieldText(tester, 'Sensor de nivel (m)'), '41');
  });

  testWidgets('al crear, el select son los proyectos de mis puntos', (
    tester,
  ) async {
    final api = _CatalogApi();
    await tester.pumpWidget(
      _card(
        point: null,
        token: 't',
        api: api,
        knownPoints: const [
          {
            'id': 1,
            'project': {'id': 9, 'name': 'Fundo'},
          },
          {
            'id': 2,
            'project': {'id': 4, 'name': 'Valle'},
          },
        ],
      ),
    );
    await tester.pump();
    expect(find.text('Nuevo punto'), findsOneWidget);
    expect(find.text('Fundo'), findsOneWidget);
    expect(api.started.containsKey('projects'), isFalse);

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    expect(find.text('Fundo').evaluate().length, greaterThanOrEqualTo(1));
    expect(find.text('Valle'), findsOneWidget);
    expect(find.text('Otro'), findsNothing);
  });

  testWidgets('si el summary no trae id, el catálogo se recorta por nombre', (
    tester,
  ) async {
    final api = _CatalogApi();
    await tester.pumpWidget(
      _card(
        point: null,
        token: 't',
        api: api,
        knownPoints: const [
          {'id': 1, 'project_name': 'Fundo'},
          {'id': 2, 'project_name': 'Valle'},
        ],
      ),
    );
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 80));
    expect(api.started.containsKey('projects'), isTrue);
    expect(find.text('Fundo'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    expect(find.text('Valle'), findsOneWidget);
    expect(find.text('Otro'), findsNothing);
  });

  testWidgets('sin código el punto queda sin cumplimiento', (tester) async {
    await tester.pumpWidget(
      _card(
        point: {
          'id': 2,
          'title': 'Canal Sur',
          'project': {'id': 9, 'name': 'Fundo'},
        },
        initialPanel: 'compliance',
      ),
    );
    await tester.pump();
    expect(find.text('Cumplimiento SMA'), findsNothing);
    expect(find.text('Cumplimiento DGA'), findsNothing);
    expect(find.byKey(const ValueKey('capture-config-code')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('capture-config-sma')));
    await tester.pump();
    expect(find.text('Cumplimiento SMA'), findsOneWidget);
    expect(_fieldText(tester, 'Código UF'), '');
    expect(
      find.byKey(const ValueKey('capture-config-sma-device')),
      findsOneWidget,
    );
  });

  testWidgets('un código sin OB abre como SMA', (tester) async {
    await tester.pumpWidget(
      _card(
        point: {
          'id': 3,
          'title': 'Descarga',
          'project': {'id': 9, 'name': 'Fundo'},
          'dga': {'code_dga': '7511', 'send_dga': false},
          'send_sma': true,
          'sma_device_id': '12180',
        },
        initialPanel: 'compliance',
      ),
    );
    await tester.pump();
    expect(find.text('Cumplimiento SMA'), findsOneWidget);
    expect(_fieldText(tester, 'Código UF'), '7511');
    expect(_fieldText(tester, 'Dispositivo SMA'), '12180');
  });

  testWidgets('el esquema se elige o se crea para el punto', (tester) async {
    final api = _CatalogApi();
    await tester.pumpWidget(
      _card(
        point: null,
        token: 't',
        api: api,
        initialPanel: 'scheme',
        knownPoints: const [
          {
            'id': 1,
            'project': {'id': 9, 'name': 'Fundo'},
          },
          {
            'id': 2,
            'project': {'id': 4, 'name': 'Valle'},
          },
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('Nuevo para este punto'), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-config-scheme')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('capture-config-add-variable')),
      findsOneWidget,
    );

    await tester.tap(find.text('Elegir existente'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('capture-config-scheme')), findsNothing);
    expect(find.text('Esquema Fundo'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    expect(find.text('Ajeno'), findsNothing);
    expect(api.started.containsKey('schemes'), isTrue);
  });

  testWidgets('sin proyectos en los puntos no se listan los ajenos', (
    tester,
  ) async {
    final api = _CatalogApi();
    await tester.pumpWidget(
      _card(point: null, token: 't', api: api, knownPoints: const []),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(api.started.containsKey('projects'), isFalse);
    expect(find.text('No hay proyectos en tus puntos.'), findsOneWidget);
    expect(find.text('Otro'), findsNothing);
  });
}

String _fieldText(WidgetTester tester, String label) {
  final field = tester.widget<TextField>(
    find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    ),
  );
  return field.controller?.text ?? '';
}

Widget _card({
  Map<String, dynamic>? point,
  String? token,
  SmartHydroApi? api,
  String? initialPanel,
  List<Map<String, dynamic>> knownPoints = const [],
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 600,
        height: 720,
        child: PointConfigCard(
          onClose: () {},
          point: point,
          token: token,
          api: api,
          initialPanel: initialPanel,
          knownPoints: knownPoints,
        ),
      ),
    ),
  );
}

Map<String, dynamic> _samplePoint() {
  return {
    'id': 6,
    'title': 'P6',
    'frecuency': 15,
    'provider': 'thethings',
    'type_dga': 'SUBTERRANEO',
    'project': {'id': 9, 'name': 'Fundo'},
    'project_name': 'Fundo',
    'lat': -33.4,
    'lon': -70.6,
    'send_dga': true,
    'code_dga': 'OB-1603-392',
    'flow_granted_dga': 12.5,
    'variables': [
      {
        'type_variable': 'CAUDAL',
        'str_variable': 'ai1',
        'label': 'Caudal pozo',
      },
    ],
    'config': {'d1': 80, 'd2': 60, 'is_telemetry': true},
  };
}

class _SlowApi extends SmartHydroApi {
  _SlowApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.local')));

  final started = <String, DateTime>{};

  Future<void> _begin(String name) async {
    started[name] = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  @override
  Future<List<Map<String, dynamic>>> projects(String token) async {
    await _begin('projects');
    return [
      {'id': 9, 'name': 'Fundo'},
    ];
  }

  @override
  Future<Map<String, dynamic>> catchmentPoint(String token, int pointId) async {
    await _begin('detail');
    return {
      'id': pointId,
      'title': 'P6',
      'frecuency': 15,
      'project': {'id': 9},
      'lat': -33.4,
      'lon': -70.6,
      'provider': 'thethings',
    };
  }

  @override
  Future<Map<String, dynamic>> pointConfig(String token, int pointId) async {
    await _begin('config');
    return {'d1': 80, 'd2': 60, 'd3': 41, 'is_telemetry': true};
  }

  @override
  Future<List<Map<String, dynamic>>> pointDgaConfigs(
    String token,
    int pointId,
  ) async {
    await _begin('dga');
    return [
      {
        'id': 3,
        'send_dga': true,
        'code_dga': 'OB-1603-392',
        'flow_granted_dga': 12.5,
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> schemesForPoint(
    String token,
    int pointId,
  ) async {
    await _begin('schemes');
    return [
      {
        'id': 2,
        'name': 'Esquema P6',
        'points_catchment': [6],
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> schemeVariables(
    String token,
    int schemeId,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return [
      {
        'id': 11,
        'type_variable': 'CAUDAL',
        'str_variable': 'ai1',
        'label': 'Caudal pozo',
      },
    ];
  }
}

class _CatalogApi extends SmartHydroApi {
  _CatalogApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.local')));

  final started = <String, DateTime>{};

  @override
  Future<List<Map<String, dynamic>>> projects(String token) async {
    started['projects'] = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    return [
      {'id': 9, 'name': 'Fundo'},
      {'id': 4, 'name': 'Valle'},
      {'id': 80, 'name': 'Otro'},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> schemes(
    String token, {
    int? pointId,
  }) async {
    started['schemes'] = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    return [
      {
        'id': 2,
        'name': 'Esquema Fundo',
        'points_catchment': [1],
      },
      {
        'id': 9,
        'name': 'Ajeno',
        'points_catchment': [80],
      },
    ];
  }
}
