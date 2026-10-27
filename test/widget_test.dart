import 'package:flutter_test/flutter_test.dart';
import 'package:voltmatch/services/catalog_service.dart';

void main() {
  test('CatalogService has standard cables', () {
    expect(CatalogService.standardCables, isNotEmpty);
  });
}
