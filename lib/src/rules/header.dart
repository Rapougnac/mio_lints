import 'dart:io';

import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

// ignore: must_be_immutable
class HeaderLintRule extends DartLintRule {
  final String? filePath;
  final String? text;
  final Map? templates;
  Directory? projectRoot;
  Map<String, List> get defaultTemplates => {
        'year': ['\\d{4}', DateTime.now().year.toString()],
        ...templates ?? {},
      };

  File get file => projectRoot!.file(filePath!).absolute;

  static final Map<String, String> _s = {};

  HeaderLintRule({
    this.filePath,
    this.text,
    this.templates,
  }) : super(
          code: _code ??
              LintCode(
                name: 'mio_header',
                problemMessage: 'Header does not match the expected template',
                correctionMessage:
                    'Update the header to match the expected template',
              ),
        );

  static LintCode? _code;

  static final schebangRegex = RegExp(r'^#!.*?\n');
  static final ignoreForFileRegex = RegExp(r'//\s*ignore_for_file:.*');

  // File _findAnaly

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    if (text != null && filePath != null) {
      throw StateError('Only one of text or filePath can be provided');
    } else if (text == null && filePath == null) {
      throw StateError('Either text or filePath must be provided');
    }

    projectRoot ??= (_findAnalysisOptionsFile(File.fromUri(resolver.source.uri)).parent);

    final rawContents = text ?? file.readAsStringSync().trimRight();

    final src = resolver.source.contents.data;

    final schebangOffset = schebangRegex.hasMatch(src)
        ? schebangRegex.firstMatch(src)?.end ?? 0
        : 0;
    // Check if there's a // ignore_for_file: comment
    final ignoreForFile = ignoreForFileRegex.hasMatch(src)
        ? (ignoreForFileRegex.firstMatch(src)?.end ?? 0) + 2
        : 0;

    final offset = schebangOffset + ignoreForFile;
    _s['offset'] = offset.toString();
    final srcHeader = _findHeader(src.substring(offset));
    _s['srcHeader'] = srcHeader;
    final header = _makeComment(rawContents);
    final trailingLines =
        '\n' * (src.substring(srcHeader.length).isEmpty ? 1 + 1 : 1);

    if (!_matchHeader(
      _stripExclamations(srcHeader.trim()),
      header,
      defaultTemplates,
    )) {
      _code = LintCode(
        name: 'mio_header',
        problemMessage: srcHeader.trim().isNotEmpty
            ? 'Header does not match the expected template'
            : 'Header is missing',
        correctionMessage: srcHeader.trim().isNotEmpty
            ? 'Update the header to match the expected template'
            : 'Add the header to match the expected template',
      );

      reporter.reportErrorForOffset(
        _code!,
        offset,
        srcHeader.length,
      );

      _s['header'] = '${_makeHeader(header, defaultTemplates)}$trailingLines';
    } else if (!srcHeader.startsWith('/*') ||
        RegExp(r'\n*$').firstMatch(srcHeader)?.group(0) != trailingLines) {
      _code = LintCode(
        name: 'mio_header',
        problemMessage: 'Header is not formatted correctly',
        correctionMessage: 'Format the header correctly',
      );

      reporter.reportErrorForOffset(
        _code!,
        offset,
        (srcHeader + trailingLines).length,
      );
      _s['header'] = srcHeader.trim() + trailingLines;
    }
  }

  File _findAnalysisOptionsFile(FileSystemEntity entity) {
    final parent = entity.parent;
    final analysisOptionsFile = parent.listSync().firstWhere(
          (e) => e.parent.analysisOptions.existsSync(),
          orElse: () => _findAnalysisOptionsFile(parent),
        );

    return analysisOptionsFile as File;
  }

  @override
  List<Fix> getFixes() => [_WriteHeader()];

  static String _makeHeader(String header, Map templates) {
    return header.replaceAllMapped(
      RegExp(r'\{(\w+)\}'),
      (match) => templates[match.group(1)]?[1] ?? match.group(0)!,
    );
  }

  String _stripExclamations(String header) {
    if (header.startsWith('/*!')) {
      return '/*${header.substring(3)}';
    }

    return header;
  }

  String _findHeader(String src) {
    final str = r'^\s*(\/\*.*?\*\/\s*)?';

    final regex = RegExp(str, dotAll: true);

    final match = regex.firstMatch(src)?.group(1);

    if (match?.startsWith('/**') == true) {
      return '';
    } else {
      return match ?? '';
    }
  }

  String _makeComment(String text) {
    if (_isComment(text)) {
      return text;
    }

    return '/*\n${text.split('\n').map((e) => ' * $e').join('\n').trimRight()}\n */';
  }

  bool _isComment(String text) {
    return text.startsWith('//') ||
        (text.startsWith('/*') && text.endsWith('*/'));
  }

  bool _matchHeader(
    String srcHeader,
    String header,
    Map<String, List> templates,
  ) {
    final body =
        (RegExp.escape(header)).split('\n').join(r'\n').replaceAllMapped(
              RegExp(r'\\\{(\w+)\\\}'),
              (match) => match.group(1) != null
                  ? (templates[match.group(1)]?[0] ?? match.group(0)!)
                  : match.group(0)!,
            );

    final re = RegExp('^$body\$');

    return re.hasMatch(srcHeader);
  }
}

class _WriteHeader extends DartFix {
  _WriteHeader();

  @override
  void run(
    CustomLintResolver resolver,
    ChangeReporter reporter,
    CustomLintContext context,
    AnalysisError error,
    List<AnalysisError> others,
  ) {
    final header = HeaderLintRule._s['header']!;
    final srcHeader = HeaderLintRule._s['srcHeader']!;

    final noHeader = srcHeader.trim().isEmpty;

    final changeBuilder = reporter.createChangeBuilder(
      message: noHeader ? 'Add header' : 'Update header',
      priority: 10,
    );

    changeBuilder.addDartFileEdit((builder) {
      if (noHeader) {
        builder.addSimpleInsertion(
          int.parse(HeaderLintRule._s['offset']!),
          header,
        );
      } else {
        builder.addSimpleReplacement(error.sourceRange, header);
      }
    });
  }
}
