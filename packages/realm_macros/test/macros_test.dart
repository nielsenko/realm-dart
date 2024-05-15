//import 'package:realm_macros/realm_macros.dart';
import 'dart:math';

import 'package:test/test.dart';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/dart/element/element.dart';

/// Create a [LibraryElement] from the given [libraryCode].
Future<ResolvedLibraryResult> libraryFromSource(String libraryCode) async {
  // The analyzer api is strictly files based, so we need to create a dummy file
  // and overlay the content of the library code to it
  const filePath = '/path/to/myFile.dart'; // dummy file path
  final collection = AnalysisContextCollection(
    includedPaths: const [filePath],
    resourceProvider: OverlayResourceProvider(PhysicalResourceProvider())
      ..setOverlay(
        filePath,
        content: libraryCode, // overlay the content of the dummy file
        modificationStamp: 0,
      ),
  );
  final analysisSession = collection.contextFor(filePath).currentSession;
  final result = await analysisSession.getResolvedLibrary(filePath);
  return result as ResolvedLibraryResult;
}

void main() {
  group('A group of tests', () {
    setUp(() {
      // Additional setup goes here.
    });

    test('First Test', () async {
      final resolvedLib = await libraryFromSource(
        r'''
import 'package:realm_macros/realm_macros.dart';

@Real mModel2()
class Person {
  String name;
  int age;
}
''',
      );
      final library = resolvedLib.element;  
      expect(library.classes, hasLength(1));
      final personClass = library.classes.first;
      expect(personClass.name, 'Person');
      expect(personClass.fields, hasLength(2));
    });
  });
}

extension on LibraryElement {
  Iterable<ClassElement> get classes => units.expand((cu) => cu.classes);
}
