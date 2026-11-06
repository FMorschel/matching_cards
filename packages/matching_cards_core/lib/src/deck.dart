import 'dart:convert';

/// The placeholder that marks where an answer goes in a prompt.
const String blankToken = '_____';

/// How many blanks a prompt has.
int blankCount(String prompt) => prompt.split(blankToken).length - 1;

/// How many answer cards a prompt needs: one per blank, and at least one.
int pickCount(String prompt) {
  final blanks = blankCount(prompt);
  return blanks < 1 ? 1 : blanks;
}

/// Writes [answers] into the blanks of [prompt], in order.
///
/// Blanks without a matching answer are left as they are.
String fillBlanks(String prompt, List<String> answers) {
  final parts = prompt.split(blankToken);
  final buffer = StringBuffer(parts.first);
  for (var i = 1; i < parts.length; i++) {
    buffer.write(i - 1 < answers.length ? answers[i - 1] : blankToken);
    buffer.write(parts[i]);
  }
  return buffer.toString();
}

/// One themed set of prompts ("black cards") and answers ("white cards").
class DeckCategory {
  const DeckCategory({
    required this.name,
    required this.black,
    required this.white,
  });

  final String name;
  final List<String> black;
  final List<String> white;
}

/// The prompts and answers of the categories chosen for one game.
class DeckPool {
  const DeckPool({required this.black, required this.white});

  final List<String> black;
  final List<String> white;
}

/// Every category the host can offer.
class DeckLibrary {
  const DeckLibrary(this.categories);

  /// Reads one or more deck files.
  ///
  /// Each file is a JSON object with a `categories` list; every category has a
  /// `name` and `black`/`white` lists of strings. Categories that share a name
  /// across files are merged. Throws a [FormatException] for anything else,
  /// including a prompt without a blank.
  factory DeckLibrary.fromJsonStrings(Iterable<String> sources) {
    final merged = <String, DeckCategory>{};
    for (final source in sources) {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('A deck file must be a JSON object.');
      }
      final entries = decoded['categories'];
      if (entries is! List) {
        throw const FormatException('A deck file needs a "categories" list.');
      }
      for (final entry in entries) {
        if (entry is! Map<String, dynamic>) {
          throw const FormatException('Every category must be an object.');
        }
        final name = entry['name'];
        if (name is! String || name.trim().isEmpty) {
          throw const FormatException('Every category needs a name.');
        }
        final black = _strings(entry['black'], name, 'black');
        final white = _strings(entry['white'], name, 'white');
        for (final prompt in black) {
          if (blankCount(prompt) < 1) {
            throw FormatException('Prompt without a blank in "$name": $prompt');
          }
        }
        final existing = merged[name];
        merged[name] = existing == null
            ? DeckCategory(name: name, black: black, white: white)
            : DeckCategory(
                name: name,
                black: [...existing.black, ...black],
                white: [...existing.white, ...white],
              );
      }
    }
    return DeckLibrary(merged.values.toList());
  }

  final List<DeckCategory> categories;

  List<String> get names => [for (final c in categories) c.name];

  /// Combines the named categories into one pool, dropping duplicate cards.
  DeckPool pool(Iterable<String> names) {
    final wanted = names.toSet();
    final black = <String>{};
    final white = <String>{};
    for (final category in categories) {
      if (!wanted.contains(category.name)) continue;
      black.addAll(category.black);
      white.addAll(category.white);
    }
    return DeckPool(black: black.toList(), white: white.toList());
  }
}

List<String> _strings(Object? value, String category, String key) {
  if (value is! List) {
    throw FormatException('Category "$category" needs a "$key" list.');
  }
  final result = <String>[];
  for (final item in value) {
    if (item is! String) {
      throw FormatException('Category "$category" has a non-text "$key" card.');
    }
    if (item.trim().isNotEmpty) result.add(item);
  }
  return result;
}
