import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'suggestion_service.dart';
import 'entry.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CalmCheckInApp());
}

class CalmCheckInApp extends StatelessWidget {
  const CalmCheckInApp({super.key});

  @override
  Widget build(BuildContext context) {
    const deepPetrol = Color(0xFF12343B);
    const slate = Color(0xFF1F2937);
    const mist = Color(0xFF273642);
    const sage = Color(0xFF84A98C);
    const cream = Color(0xFFFAF7F2);

    final theme = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: sage,
        secondary: sage,
        surface: mist,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: cream,
        error: Color(0xFFE11D48),
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: slate,
      appBarTheme: const AppBarTheme(
        backgroundColor: deepPetrol,
        foregroundColor: cream,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: mist,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF111827),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Calm Check-in',
      theme: theme,
      home: const HomeScreen(),
    );
  }
}

class SuggestionCard extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;

  const SuggestionCard({
    super.key,
    required this.text,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15), // Transparenter Schimmer
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Storage {
  static const _key = 'calm_check_in_entries_v1';

  static Future<List<Entry>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.trim().isEmpty) {
      return [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return [];
    }
    final entries = decoded
        .whereType<Map>()
        .map((m) => Entry.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    entries.sort((a, b) => a.date.compareTo(b.date));
    return entries;
  }

  static Future<void> save(List<Entry> entries) async {
    final sp = await SharedPreferences.getInstance();
    final raw = jsonEncode(entries.map((e) => e.toJson()).toList());
    await sp.setString(_key, raw);
  }

  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
  }
}

int clampInt(int v, int min, int max) => v < min ? min : (v > max ? max : v);
double clampDouble(double v, double min, double max) =>
    v < min ? min : (v > max ? max : v);



String todayIso() {
  final now = DateTime.now();
  return DateFormat('yyyy-MM-dd').format(now);
}

String ddmm(String iso) {
  final dt = DateTime.parse(iso);
  return DateFormat('dd.MM').format(dt);
}

const symptomsList = <Map<String, String>>[
  {'key': 'exhaustion', 'label': 'Erschöpfung'},
  {'key': 'sleep', 'label': 'Schlafprobleme'},
  {'key': 'irritability', 'label': 'Reizbarkeit'},
  {'key': 'anxiety', 'label': 'Anspannung/Angst'},
  {'key': 'focus', 'label': 'Konzentration weg'},
  {'key': 'headache', 'label': 'Kopf-/Nackenschmerz'},
  {'key': 'detached', 'label': 'Innerlich leer'},
  {'key': 'overwhelm', 'label': 'Überforderung'},
];

const actionsList = <Map<String, String>>[
  {'key': 'walk', 'label': '10–20 Min. Spaziergang'},
  {'key': 'breathing', 'label': '3 Min. Atmung'},
  {'key': 'water', 'label': 'Wasser + Snack'},
  {'key': 'pause', 'label': 'Bildschirm-Pause'},
  {'key': 'boundary', 'label': 'Grenze gesetzt (Nein gesagt)'},
  {'key': 'reachout', 'label': 'Jemanden kontaktiert'},
  {'key': 'sleepRoutine', 'label': 'Schlafroutine'},
  {'key': 'therapy', 'label': 'Hilfe/Termin geplant'},
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Entry> entries = [];
  String selectedDate = todayIso();

  int energy = 5;
  int stress = 5;
  double sleepHours = 7;
  int mood = 5;
  String notes = '';
  List<String> symptoms = [];
  List<String> actions = [];
  late TextEditingController _notesController;
  bool loading = true;

   final SuggestionService _suggestionService = SuggestionService();

  Entry? get latest => entries.isEmpty ? null : entries.last;
  int get latestScore => latest == null ? 0 : latest!.calculateRiskScore();
  String get suggestion => _suggestionService.getSuggestion(latestScore, latest);


  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: notes);
    _load();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final loaded = await Storage.load();
    if (!mounted) {
      return;
    }
    setState(() {
      entries = loaded;
      loading = false;
    });
    _hydrateFormForDate(selectedDate);
  }

  void _hydrateFormForDate(String date) {
    final existing = entries.where((e) => e.date == date).toList();
    if (existing.isNotEmpty) {
      final e = existing.first;
      setState(() {
        energy = e.energy;
        stress = e.stress;
        sleepHours = e.sleepHours;
        mood = e.mood;
        notes = e.notes;
        _notesController.text = notes;
        symptoms = List<String>.from(e.symptoms);
        actions = List<String>.from(e.actions);
      });
    } else {
      setState(() {
        energy = 5;
        stress = 5;
        sleepHours = 7;
        mood = 5;
        notes = '';
        _notesController.text = '';
        symptoms = [];
        actions = [];
      });
    }
  }

    bool get hasEntryForSelected => entries.any((e) => e.date == selectedDate);

  Future<void> saveEntry() async {
    final newEntry = Entry(
      date: selectedDate,
      energy: clampInt(energy, 0, 10),
      stress: clampInt(stress, 0, 10),
      sleepHours: clampDouble(sleepHours, 0, 14),
      mood: clampInt(mood, 0, 10),
      symptoms: List<String>.from(symptoms),
      actions: List<String>.from(actions),
      notes: notes.trim(),
      updatedAt: DateTime.now().toIso8601String(),
    );

    final next = entries.where((e) => e.date != selectedDate).toList()
      ..add(newEntry);
    next.sort((a, b) => a.date.compareTo(b.date));

    setState(() => entries = next);
    await Storage.save(next);

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(hasEntryForSelected
              ? 'Eintrag aktualisiert.'
              : 'Eintrag gespeichert.')),
    );
  }

  Future<void> deleteEntry(String date) async {
    final next = entries.where((e) => e.date != date).toList();
    setState(() => entries = next);
    await Storage.save(next);
    _hydrateFormForDate(selectedDate);
  }

  Future<void> clearAll() async {
    await Storage.clear();
    setState(() {
      entries = [];
    });
    _hydrateFormForDate(selectedDate);
  }

  List<Entry> get last7 =>
      entries.length <= 7 ? entries : entries.sublist(entries.length - 7);

  double avgNum(Iterable<num> xs) =>
      xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

  Future<File> _writeTempFile(String filename, String content) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content, flush: true);
    return file;
  }

  Future<void> exportFilteredCSV(
      {required List<Entry> dataToExport, required String reportName}) async {
    if (dataToExport.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Keine Einträge für diesen Zeitraum gefunden!'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    final rows = <List<dynamic>>[
      [
        'Datum',
        'Energie',
        'Stress',
        'Schlaf',
        'Stimmung',
        'Symptome',
        'Aktionen',
        'Notizen'
      ]
    ];

    for (final e in dataToExport) {
      rows.add([
        e.date,
        e.energy,
        e.stress,
        e.sleepHours,
        e.mood,
        e.symptoms.join(';'),
        e.actions.join(';'),
        e.notes,
      ]);
    }

    final csvString = rows
        .map((row) => row
            .map((item) => '"${item.toString().replaceAll('"', '""')}"')
            .join(','))
        .join('\n');

    final file = await _writeTempFile('CalmCheckIn_$reportName.csv', csvString);

    await Share.shareXFiles([XFile(file.path)],
        subject: 'Mein $reportName',
        text: 'Hier ist mein Calm Check-in Bericht für $reportName.');

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('$reportName erfolgreich exportiert!'),
          backgroundColor: Colors.green),
    );
  }

  Future<void> exportBackupJson() async {
    final payload = {
      'app': 'calm_check_in',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'entries': entries.map((e) => e.toJson()).toList(),
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
    final file = await _writeTempFile(
        'calm-check-in-backup-${todayIso()}.json', jsonStr);

    await Share.shareXFiles([XFile(file.path)], text: 'Calm Check-in – Backup');
  }

  Future<void> restoreFromBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }

    final path = result.files.single.path;
    if (path == null) {
      return;
    }

    final file = File(path);
    final raw = await file.readAsString();

    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw Exception('Ungültiges Backup-Format.');
    }

    final ent = decoded['entries'];
    if (ent is! List) {
      throw Exception('Backup enthält keine Einträge.');
    }

    final restored = ent
        .whereType<Map>()
        .map((m) => Entry.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    restored.sort((a, b) => a.date.compareTo(b.date));

    setState(() => entries = restored);
    await Storage.save(restored);
    _hydrateFormForDate(selectedDate);

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backup importiert.')),
    );
  }

  void showDisclaimer() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Wichtiger Hinweis'),
        content: const Text(
          'Calm Check-in ist kein medizinisches Tool und ersetzt keine Diagnose oder Therapie.\n\n'
          'Wenn es dir akut schlecht geht oder du dich unsicher fühlst, hol dir bitte Unterstützung im echten Leben '
          '(Ärzt*in, Therapeut*in, Vertrauensperson, lokale Krisendienste).',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Ok')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final latestEntry = latest;
    final score = latestEntry == null ? null : latestScore;

    final weekly = last7;
    final weeklyStats = weekly.isEmpty
        ? null
        : {
      'risk': avgNum(weekly.map((e) => e.calculateRiskScore())),
            'energy': avgNum(weekly.map((e) => e.energy)),
            'stress': avgNum(weekly.map((e) => e.stress)),
            'mood': avgNum(weekly.map((e) => e.mood)),
            'sleep': avgNum(weekly.map((e) => e.sleepHours)),
          };

    final chartEntries =
        entries.length <= 30 ? entries : entries.sublist(entries.length - 30);
    final chartSpots = <FlSpot>[];
    for (int i = 0; i < chartEntries.length; i++) {
      chartSpots.add(
          FlSpot(i.toDouble(), chartEntries[i].calculateRiskScore().toDouble()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calm Check-in'),
        actions: [
          IconButton(
            tooltip: 'Feedback senden',
            onPressed: () async {
              final String subject =
                  Uri.encodeComponent('Feedback zu Calm Check-in');
              final String body = Uri.encodeComponent(
                  'Hallo Chris,\n\nhier ist mein Feedback zur App:\n');
              final Uri mailUri = Uri.parse(
                  'mailto:info.christian.zindel@gmx.de?subject=$subject&body=$body');

              if (await canLaunchUrl(mailUri)) {
                await launchUrl(mailUri);
              } else {
                await Share.share('Mein Feedback zur App: ',
                    subject: 'Feedback');
              }
            },
            icon: const Icon(Icons.chat_bubble_outline),
          ),
          IconButton(
            tooltip: 'Hinweis',
            onPressed: showDisclaimer,
            icon: const Icon(Icons.info_outline),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              try {
                if (v == 'csv') {
                  await exportFilteredCSV(
                    dataToExport: entries,
                    reportName: 'Gesamtbericht',
                  );
                }
                if (v == 'backup') {
                  await exportBackupJson();
                }
                if (v == 'restore') {
                  await restoreFromBackup();
                }
                if (v == 'clear') {
                  if (!mounted) {
                    return;
                  }
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Alles löschen?'),
                      content: const Text(
                          'Das entfernt alle Einträge aus diesem Gerät.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(dialogContext, false),
                            child: const Text('Abbrechen')),
                        TextButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text('Löschen')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await clearAll();
                  }
                }
              } catch (e) {
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Fehler: $e')),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'csv', child: Text('CSV Export')),
              PopupMenuItem(
                  value: 'backup', child: Text('Backup exportieren (JSON)')),
              PopupMenuItem(
                  value: 'restore', child: Text('Backup importieren')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'clear', child: Text('Alles löschen')),
            ],
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Aktueller Belastungs-Index',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(
                          latestEntry == null
                              ? 'Noch keine Daten'
                              : 'Letzter Eintrag: ${latestEntry.date}',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75)),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                score == null ? '–' : '$score / 100',
                                style: const TextStyle(
                                    fontSize: 34, fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (score != null) _RiskPill(score: score),
                          ],
                        ),
                        if (latestEntry != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.10)),
                            ),
                            child: Text(
                              suggestion,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Verlauf (letzte 30 Einträge)',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 200,
                          child: chartEntries.length < 2
                              ? Text(
                                  'Trage ein paar Tage ein, dann erscheint hier der Verlauf.',
                                  style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.75)))
                              : LineChart(
                                  LineChartData(
                                    minY: 0,
                                    maxY: 100,
                                    gridData: const FlGridData(show: true),
                                    borderData: FlBorderData(show: true),
                                    titlesData: FlTitlesData(
                                      rightTitles: const AxisTitles(
                                          sideTitles:
                                              SideTitles(showTitles: false)),
                                      topTitles: AxisTitles(
                                          sideTitles:
                                              SideTitles(showTitles: false)),
                                      leftTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 34,
                                          getTitlesWidget: (v, meta) => Text(
                                            v.toInt().toString(),
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.white
                                                    .withValues(alpha: 0.7)),
                                          ),
                                        ),
                                      ),
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 26,
                                          interval: (chartEntries.length / 4)
                                              .clamp(1, 999)
                                              .toDouble(),
                                          getTitlesWidget: (v, meta) {
                                            final idx = v.toInt();
                                            if (idx < 0 ||
                                                idx >= chartEntries.length) {
                                              return const SizedBox.shrink();
                                            }
                                            return Text(
                                              ddmm(chartEntries[idx].date),
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.7)),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    lineBarsData: [
                                      LineChartBarData(
                                        spots: chartSpots,
                                        isCurved: true,
                                        barWidth: 3,
                                        dotData: const FlDotData(show: false),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Hinweis: Das ist kein Diagnose-Tool. Es hilft nur, Muster zu sehen.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Wochenschnitt',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        if (weeklyStats == null)
                          Text(
                              'Trage ein paar Tage ein, dann siehst du hier Trends.',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75)))
                        else
                          Column(
                            children: [
                              _statRow('Ø Risk',
                                  '${(weeklyStats['risk']!).round()}/100'),
                              _statRow('Ø Energie',
                                  '${weeklyStats['energy']!.toStringAsFixed(1)}/10'),
                              _statRow('Ø Stress',
                                  '${weeklyStats['stress']!.toStringAsFixed(1)}/10'),
                              _statRow('Ø Stimmung',
                                  '${weeklyStats['mood']!.toStringAsFixed(1)}/10'),
                              _statRow('Ø Schlaf',
                                  '${weeklyStats['sleep']!.toStringAsFixed(1)}h'),
                            ],
                          )
                      ],
                    ),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Daily Check-in',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: InputDecorator(
                                decoration:
                                    const InputDecoration(labelText: 'Datum'),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: selectedDate,
                                    isExpanded: true,
                                    items: _dateOptions(entries).map((d) {
                                      return DropdownMenuItem(
                                        value: d,
                                        child: Text(d),
                                      );
                                    }).toList(),
                                    onChanged: (v) {
                                      if (v == null) {
                                        return;
                                      }
                                      setState(() => selectedDate = v);
                                      _hydrateFormForDate(v);
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: () {
                                final d = todayIso();
                                setState(() => selectedDate = d);
                                _hydrateFormForDate(d);
                              },
                              child: const Text('Heute'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _sliderInt('Energie', energy,
                            (v) => setState(() => energy = v),
                            left: 'leer', right: 'voll'),
                        _sliderInt(
                            'Stress', stress, (v) => setState(() => stress = v),
                            left: 'ruhig', right: 'unter Druck'),
                        _sliderInt(
                            'Stimmung', mood, (v) => setState(() => mood = v),
                            left: 'schwer', right: 'ok'),
                        _sliderDouble('Schlaf (Stunden)', sleepHours,
                            (v) => setState(() => sleepHours = v),
                            min: 0, max: 14),
                        const SizedBox(height: 10),
                        _chipsSection(
                          title: 'Symptome (optional)',
                          items: symptomsList,
                          selected: symptoms,
                          onToggle: (k) => setState(() {
                            symptoms = symptoms.contains(k)
                                ? (symptoms..remove(k))
                                : (symptoms..add(k));
                            symptoms = List<String>.from(symptoms);
                          }),
                        ),
                        const SizedBox(height: 10),
                        _chipsSection(
                          title: 'Was hat geholfen? (optional)',
                          items: actionsList,
                          selected: actions,
                          onToggle: (k) => setState(() {
                            actions = actions.contains(k)
                                ? (actions..remove(k))
                                : (actions..add(k));
                            actions = List<String>.from(actions);
                          }),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _notesController,
                          minLines: 3,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            labelText: 'Notizen (optional)',
                            hintText:
                                'Ein Satz reicht. Was war heute schwierig – oder gut?',
                          ),
                          onChanged: (v) => setState(() => notes = v),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: saveEntry,
                                child: Text(hasEntryForSelected
                                    ? 'Aktualisieren'
                                    : 'Speichern'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            if (hasEntryForSelected)
                              OutlinedButton(
                                onPressed: () => deleteEntry(selectedDate),
                                child: const Text('Löschen'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Einträge',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        if (entries.isEmpty)
                          Text('Noch keine Einträge.',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75)))
                        else
                          Column(
                            children: entries.reversed.take(12).map((e) {
                              final r = e.calculateRiskScore();
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(e.date),
                                subtitle: Text(
                                    'Energie ${e.energy}/10 · Stress ${e.stress}/10 · Schlaf ${e.sleepHours}h',
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.7))),
                                trailing: _RiskPill(score: r),
                                onTap: () {
                                  setState(() => selectedDate = e.date);
                                  _hydrateFormForDate(e.date);
                                },
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'v1.0 · Calm Check-in · lokal gespeichert',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  List<String> _dateOptions(List<Entry> entries) {
    final set = <String>{todayIso(), ...entries.map((e) => e.date)};
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style:
                      TextStyle(color: Colors.white.withValues(alpha: 0.75)))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _sliderInt(String label, int value, ValueChanged<int> onChanged,
      {String? left, String? right}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9)))),
              Text('$value/10',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          Slider(
            min: 0,
            max: 10,
            divisions: 10,
            value: value.toDouble(),
            onChanged: (v) => onChanged(v.round()),
          ),
          if (left != null && right != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(left,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.55))),
                Text(right,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.55))),
              ],
            ),
        ],
      ),
    );
  }

  Widget _sliderDouble(
      String label, double value, ValueChanged<double> onChanged,
      {required double min, required double max}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9)))),
              Text('${value.toStringAsFixed(1)}h',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          Slider(
            min: min,
            max: max,
            divisions: ((max - min) * 2).round(),
            value: value,
            onChanged: (v) => onChanged(double.parse(v.toStringAsFixed(1))),
          ),
        ],
      ),
    );
  }

  Widget _chipsSection({
    required String title,
    required List<Map<String, String>> items,
    required List<String> selected,
    required void Function(String key) onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((it) {
            final k = it['key']!;
            final label = it['label']!;
            final isOn = selected.contains(k);
            return FilterChip(
              selected: isOn,
              label: Text(label),
              onSelected: (_) => onToggle(k),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _RiskPill extends StatelessWidget {
  final int score;
  const _RiskPill({required this.score});

  @override
  Widget build(BuildContext context) {
    String text;
    Color color;
    if (score >= 75) {
      text = 'hoch';
      color = const Color(0xFFE11D48);
    } else if (score >= 50) {
      text = 'mittel';
      color = const Color(0xFFF59E0B);
    } else if (score >= 30) {
      text = 'moderat';
      color = const Color(0xFF60A5FA);
    } else {
      text = 'niedrig';
      color = const Color(0xFF84A98C);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text('$score · $text',
          style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    );
  }
}
