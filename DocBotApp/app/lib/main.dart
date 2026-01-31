import "dart:convert";
import "dart:io";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:image_picker/image_picker.dart";
import "package:http/http.dart" as http;
import "package:path_provider/path_provider.dart";
import "package:open_filex/open_filex.dart";
import "package:share_plus/share_plus.dart";
import "package:speech_to_text/speech_to_text.dart" as stt;
import "package:shared_preferences/shared_preferences.dart";
import "package:permission_handler/permission_handler.dart";
import "package:flutter_contacts/flutter_contacts.dart";
import "package:url_launcher/url_launcher.dart";
import "package:record/record.dart";
import "package:photo_manager/photo_manager.dart";
import "package:in_app_update/in_app_update.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:flutter/services.dart";
import "l10n/strings.dart";
import "local/history_store.dart";

const String _apiBaseUrlEnv = String.fromEnvironment("API_BASE_URL", defaultValue: "");
const String _iosBundleId = "com.example.docbot_app";
const String _iosAppStoreId = "";

String resolveApiBaseUrl() {
  if (_apiBaseUrlEnv.isNotEmpty) {
    return _apiBaseUrlEnv;
  }
  if (kIsWeb) {
    return "http://localhost:8000";
  }
  if (Platform.isAndroid) {
    return "http://10.0.2.2:8000";
  }
  if (Platform.isIOS) {
    return "http://localhost:8000";
  }
  return "http://localhost:8000";
}

final String apiBaseUrl = resolveApiBaseUrl();
final ValueNotifier<Locale> appLocale = ValueNotifier(const Locale("he", "IL"));
final ValueNotifier<bool> isLoggedIn = ValueNotifier(false);
final ValueNotifier<String?> currentUserKey = ValueNotifier(null);

void toggleLocale() {
  final current = appLocale.value.languageCode;
  appLocale.value = current == "he" ? const Locale("en", "US") : const Locale("he", "IL");
}

List<Widget> appBarActions(
  BuildContext context, {
  bool showLogout = false,
  bool showCancelReport = false,
  List<PopupMenuEntry<String>>? extraItems,
  void Function(String)? onSelected,
}) {
  return [
    PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == "language") {
          toggleLocale();
        } else if (value == "cancel_report") {
          onSelected?.call(value);
        } else if (value == "logout") {
          logout(context);
        } else if (value == "exit_app") {
          SystemNavigator.pop();
        } else {
          onSelected?.call(value);
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[
          if (extraItems != null) ...extraItems,
          if (showCancelReport)
            PopupMenuItem<String>(
              value: "cancel_report",
              child: Text(t(context, "cancel_report_button")),
            ),
          PopupMenuItem<String>(
            value: "language",
            child: Text(t(context, "toggle_language")),
          ),
        ];
        if (showLogout) {
          items.add(
            PopupMenuItem<String>(
              value: "logout",
              child: Text(t(context, "logout_button")),
            ),
          );
        }
        items.add(
          PopupMenuItem<String>(
            value: "exit_app",
            child: Text(t(context, "exit_app_button")),
          ),
        );
        return items;
      },
    ),
  ];
}

TextDirection _textDirection(BuildContext context) {
  return Localizations.localeOf(context).languageCode == "he"
      ? TextDirection.rtl
      : TextDirection.ltr;
}

TextAlign _textAlign(BuildContext context) {
  return Localizations.localeOf(context).languageCode == "he"
      ? TextAlign.right
      : TextAlign.left;
}

String _safeFilePart(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return "";
  final sanitized = trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]+'), "_");
  return sanitized.replaceAll(RegExp(r"\s+"), "_");
}

String _deriveUserKey(Map<String, dynamic> profile) {
  final email = (profile["email"] ?? "").toString().trim().toLowerCase();
  if (email.isNotEmpty) {
    return "email:$email";
  }
  final userId = (profile["user_id"] ?? "").toString().trim();
  return "user:$userId";
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString("auth_token");
  if (token != null && token.isNotEmpty) {
    api.token = token;
    isLoggedIn.value = true;
    final storedKey = prefs.getString("current_user_key");
    if (storedKey != null && storedKey.isNotEmpty) {
      currentUserKey.value = storedKey;
    } else {
      try {
        final profile = await api.getCurrentUser();
        final key = _deriveUserKey(profile);
        currentUserKey.value = key;
        await prefs.setString("current_user_key", key);
      } catch (_) {}
    }
    await _cleanupLegacyHistory();
  }
  runApp(const DocBotApp());
}

Future<void> _cleanupLegacyHistory() async {
  const legacyKeys = [
    "history_locations",
    "history_contact_names",
    "history_contact_emails",
    "history_descriptions",
    "history_notes",
  ];
  final removed = await HistoryStore.clearLegacyHistory(legacyKeys);
  if (removed.isNotEmpty) {
    debugPrint("Cleared legacy history keys: ${removed.join(", ")}");
  }
}

class DocBotApp extends StatelessWidget {
  const DocBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocale,
      builder: (context, locale, _) {
        final isRtl = locale.languageCode == "he";
        return MaterialApp(
          title: "DocBotApp",
          theme: ThemeData(useMaterial3: true),
          locale: locale,
          supportedLocales: const [Locale("he", "IL"), Locale("en", "US")],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => UpdateChecker(
            child: Directionality(
              textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          home: ValueListenableBuilder<bool>(
            valueListenable: isLoggedIn,
            builder: (context, loggedIn, _) {
              return loggedIn ? const StartReportScreen() : const LoginScreen();
            },
          ),
        );
      },
    );
  }
}

class UpdateChecker extends StatefulWidget {
  const UpdateChecker({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends State<UpdateChecker> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
    }
  }

  Future<void> _checkForUpdate() async {
    if (_checked) return;
    _checked = true;
    try {
      if (Platform.isAndroid) {
        final info = await InAppUpdate.checkForUpdate();
        if (info.updateAvailability == UpdateAvailability.updateAvailable) {
          if (info.immediateUpdateAllowed) {
            await InAppUpdate.performImmediateUpdate();
          } else if (info.flexibleUpdateAllowed) {
            await InAppUpdate.startFlexibleUpdate();
            await InAppUpdate.completeFlexibleUpdate();
          }
        }
      } else if (Platform.isIOS) {
        await _checkIosUpdate();
      }
    } catch (_) {}
  }

  Future<void> _checkIosUpdate() async {
    if (_iosBundleId.isEmpty || !mounted) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final resp = await http.get(
        Uri.parse("https://itunes.apple.com/lookup?bundleId=$_iosBundleId"),
      );
      if (resp.statusCode != 200) return;
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final results = (data["results"] as List?) ?? [];
      if (results.isEmpty) return;
      final storeVersion = results.first["version"]?.toString() ?? "";
      final storeUrl =
          results.first["trackViewUrl"]?.toString() ?? (_iosAppStoreId.isNotEmpty
              ? "https://apps.apple.com/app/id$_iosAppStoreId"
              : "");
      if (storeVersion.isEmpty || storeUrl.isEmpty) return;
      if (_isNewerVersion(storeVersion, info.version)) {
        await _showIosUpdateDialog(storeUrl);
      }
    } catch (_) {}
  }

  bool _isNewerVersion(String store, String current) {
    List<int> parse(String v) => v.split(".").map((e) => int.tryParse(e) ?? 0).toList();
    final a = parse(store);
    final b = parse(current);
    final len = a.length > b.length ? a.length : b.length;
    for (int i = 0; i < len; i++) {
      final ai = i < a.length ? a[i] : 0;
      final bi = i < b.length ? b[i] : 0;
      if (ai > bi) return true;
      if (ai < bi) return false;
    }
    return false;
  }

  Future<void> _showIosUpdateDialog(String storeUrl) async {
    if (!mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(context, "update_available_title")),
        content: Text(t(context, "update_available_body")),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(context, "later_button")),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t(context, "update_button")),
          ),
        ],
      ),
    );
    if (proceed == true) {
      final uri = Uri.parse(storeUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class TemplateInfo {
  TemplateInfo({required this.key, required this.title});

  final String key;
  final String title;

  factory TemplateInfo.fromJson(Map<String, dynamic> json) {
    return TemplateInfo(key: json["key"], title: json["title"]);
  }
}

class ContactInfo {
  ContactInfo({
    required this.id,
    required this.name,
    required this.email,
    this.company,
    this.roleTitle,
    this.phone,
  });

  final String id;
  final String name;
  final String email;
  final String? company;
  final String? roleTitle;
  final String? phone;

  factory ContactInfo.fromJson(Map<String, dynamic> json) {
    return ContactInfo(
      id: json["id"],
      name: json["name"],
      email: json["email"],
      company: json["company"],
      roleTitle: json["role_title"],
      phone: json["phone"],
    );
  }
}

class ReportSummary {
  ReportSummary({
    required this.reportId,
    required this.createdAt,
    required this.location,
    required this.templateKey,
    required this.title,
    required this.folder,
    required this.tags,
  });

  final String reportId;
  final String createdAt;
  final String location;
  final String templateKey;
  final String title;
  final String folder;
  final List<String> tags;

  factory ReportSummary.fromJson(Map<String, dynamic> json) {
    return ReportSummary(
      reportId: json["report_id"],
      createdAt: json["created_at"],
      location: json["location"] ?? "",
      templateKey: json["template_key"] ?? "",
      title: json["title"] ?? "",
      folder: json["folder"] ?? "",
      tags: (json["tags"] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

class ReportItemData {
  ReportItemData({
    required this.id,
    required this.number,
    required this.description,
    required this.notes,
  });

  final String id;
  final String number;
  final String description;
  final String notes;

  factory ReportItemData.fromJson(Map<String, dynamic> json) {
    return ReportItemData(
      id: json["id"],
      number: json["number"],
      description: json["description"] ?? "",
      notes: json["notes"] ?? "",
    );
  }
}

class ReportPhotoData {
  ReportPhotoData({required this.id, required this.itemId});

  final String id;
  final String? itemId;

  factory ReportPhotoData.fromJson(Map<String, dynamic> json) {
    return ReportPhotoData(
      id: json["id"],
      itemId: json["item_id"],
    );
  }
}

class ActiveSessionData {
  ActiveSessionData({
    required this.items,
    required this.photos,
    required this.location,
    required this.title,
    required this.templateKey,
    required this.attendees,
    required this.distributionList,
  });

  final List<ReportItemData> items;
  final List<ReportPhotoData> photos;
  final String location;
  final String title;
  final String templateKey;
  final List<String> attendees;
  final List<String> distributionList;
}

class ApiClient {
  String? token;

  Future<Map<String, dynamic>> getCurrentUser() async {
    final resp = await http.get(
      Uri.parse("$apiBaseUrl/auth/me"),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    return _decodeJson(resp) as Map<String, dynamic>;
  }

  dynamic _decodeJson(http.Response resp) {
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  Future<String> login(String phone, String password) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/auth/login"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"phone": phone, "password": password}),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    return (_decodeJson(resp) as Map<String, dynamic>)["access_token"] as String;
  }

  Future<String> register(String phone, String password) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/auth/register"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"phone": phone, "password": password}),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    return (_decodeJson(resp) as Map<String, dynamic>)["access_token"] as String;
  }

  Future<void> requestEmailCode(String phone, String email, String password) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/auth/request_email_code"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"phone": phone, "email": email, "password": password}),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
  }

  Future<String> verifyEmailCode(String phone, String code) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/auth/verify_email"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"phone": phone, "code": code}),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    return (_decodeJson(resp) as Map<String, dynamic>)["access_token"] as String;
  }

  Future<List<String>> listLocations() async {
    final resp = await http.get(
      Uri.parse("$apiBaseUrl/reports/locations"),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    final data = _decodeJson(resp) as Map<String, dynamic>;
    return (data["locations"] as List).map((e) => e.toString()).toList();
  }

  Future<List<ReportSummary>> listRecentReports() async {
    final resp = await http.get(
      Uri.parse("$apiBaseUrl/reports/recent"),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    final data = _decodeJson(resp) as Map<String, dynamic>;
    final items = (data["reports"] as List).cast<Map<String, dynamic>>();
    return items.map(ReportSummary.fromJson).toList();
  }

  Future<void> openReport(String reportId) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/reports/$reportId/open"),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
  }

  Future<ActiveSessionData> getActiveSession() async {
    final resp = await http.get(
      Uri.parse("$apiBaseUrl/reports/session"),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    final data = _decodeJson(resp) as Map<String, dynamic>;
    final session = data["session"] as Map<String, dynamic>;
    final items = (session["items"] as List).cast<Map<String, dynamic>>();
    final photos = (session["photos"] as List? ?? []).cast<Map<String, dynamic>>();
    return ActiveSessionData(
      items: items.map(ReportItemData.fromJson).toList(),
      photos: photos.map(ReportPhotoData.fromJson).toList(),
      location: session["location"]?.toString() ?? "",
      title: session["title"]?.toString() ?? "",
      templateKey: session["template_key"]?.toString() ?? "",
      attendees: (session["attendees"] as List? ?? []).map((e) => e.toString()).toList(),
      distributionList:
          (session["distribution_list"] as List? ?? []).map((e) => e.toString()).toList(),
    );
  }

  Future<void> updateItem(String itemId, String description, String notes) async {
    final resp = await http.put(
      Uri.parse("$apiBaseUrl/reports/item/$itemId"),
      headers: _headers(),
      body: jsonEncode({"description": description, "notes": notes}),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
  }

  Future<void> organizeReport(String reportId, String folder, List<String> tags) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/reports/$reportId/organize"),
      headers: _headers(),
      body: jsonEncode({"folder": folder, "tags": tags}),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
  }

  Future<void> startReport(String location, String templateKey) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/reports/start"),
      headers: _headers(),
      body: jsonEncode({"location": location, "template_key": templateKey}),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
  }

  Future<String> addItem(String description, String notes) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/reports/item"),
      headers: _headers(),
      body: jsonEncode({"description": description, "notes": notes}),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    return (_decodeJson(resp) as Map<String, dynamic>)["item_id"] as String;
  }

  Future<void> uploadPhoto(File file, {String? itemId}) async {
    final req = http.MultipartRequest("POST", Uri.parse("$apiBaseUrl/reports/photo"));
    if (token != null) {
      req.headers["Authorization"] = "Bearer $token";
    }
    if (itemId != null) {
      req.fields["item_id"] = itemId;
    }
    req.files.add(await http.MultipartFile.fromPath("file", file.path));
    final resp = await req.send();
    if (resp.statusCode != 200) {
      throw Exception(await resp.stream.bytesToString());
    }
  }

  Future<List<TemplateInfo>> listTemplates() async {
    final resp = await http.get(
      Uri.parse("$apiBaseUrl/reports/templates"),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    final data = _decodeJson(resp) as Map<String, dynamic>;
    final items = (data["templates"] as List).cast<Map<String, dynamic>>();
    return items.map(TemplateInfo.fromJson).toList();
  }

  Future<List<ContactInfo>> listContacts() async {
    final resp = await http.get(
      Uri.parse("$apiBaseUrl/contacts"),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    final data = _decodeJson(resp) as Map<String, dynamic>;
    final items = (data["contacts"] as List).cast<Map<String, dynamic>>();
    return items.map(ContactInfo.fromJson).toList();
  }

  Future<ContactInfo> addContact({
    required String name,
    required String email,
    String? company,
    String? roleTitle,
    String? phone,
  }) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/contacts"),
      headers: _headers(),
      body: jsonEncode({
        "name": name,
        "email": email,
        "company": company,
        "role_title": roleTitle,
        "phone": phone,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    final data = _decodeJson(resp) as Map<String, dynamic>;
    return ContactInfo.fromJson(data["contact"]);
  }

  Future<void> setReportContacts({
    required List<String> attendees,
    required List<String> distributionList,
  }) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/reports/contacts"),
      headers: _headers(),
      body: jsonEncode({
        "attendees": attendees,
        "distribution_list": distributionList,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
  }

  Future<String> finalizeAndSave({String? filename}) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/reports/finalize"),
      headers: _headers(json: false),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    final dir = await getApplicationDocumentsDirectory();
    final fallback = "Report_${DateTime.now().millisecondsSinceEpoch}.docx";
    final name = (filename == null || filename.isEmpty) ? fallback : filename;
    final finalName = name.endsWith(".docx") ? name : "$name.docx";
    final file = File("${dir.path}/$finalName");
    await file.writeAsBytes(resp.bodyBytes);
    return file.path;
  }

  Future<void> cancelReport() async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/reports/cancel"),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
  }

  Map<String, String> _headers({bool json = true}) {
    final headers = <String, String>{};
    if (token != null) {
      headers["Authorization"] = "Bearer $token";
    }
    if (json) {
      headers["Content-Type"] = "application/json";
    }
    return headers;
  }
}

final api = ApiClient();

Future<void> logout(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove("auth_token");
  await prefs.remove("current_user_key");
  api.token = null;
  currentUserKey.value = null;
  isLoggedIn.value = false;
  if (context.mounted) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final emailController = TextEditingController();
  String? error;
  bool loading = false;
  bool emailEditable = false;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString("saved_email") ?? "";
    if (savedEmail.isNotEmpty) {
      emailController.text = savedEmail;
      setState(() => emailEditable = false);
    } else {
      setState(() => emailEditable = true);
    }
  }

  Future<void> _auth() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final phone = phoneController.text.trim();
      final password = passwordController.text;
      try {
        final token = await api.login(phone, password);
        await _saveToken(token);
        if (mounted) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const StartReportScreen()));
        }
        return;
      } catch (_) {
        setState(() => emailEditable = true);
        final email = emailController.text.trim();
        if (email.isEmpty) {
          setState(() => error = t(context, "error_email_required"));
          return;
        }
        final accepted = await _showTermsAndAccept();
        if (!accepted) {
          setState(() => error = t(context, "email_verification_failed"));
          return;
        }
        await api.requestEmailCode(phone, email, password);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t(context, "email_verification_sent"))),
          );
        }
        final code = await _promptForCode();
        if (code == null || code.isEmpty) {
          setState(() => error = t(context, "email_verification_failed"));
          return;
        }
        final token = await api.verifyEmailCode(phone, code);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("saved_email", email);
        await _saveToken(token);
      }
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _saveToken(String token) async {
    api.token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("auth_token", token);
    try {
      final profile = await api.getCurrentUser();
      final key = _deriveUserKey(profile);
      currentUserKey.value = key;
      await prefs.setString("current_user_key", key);
    } catch (_) {}
    isLoggedIn.value = true;
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const StartReportScreen()));
    }
  }

  Future<bool> _showTermsAndAccept() async {
    bool accepted = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t(context, "terms_title")),
        content: SingleChildScrollView(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "This is a beta, experimental application provided \"as is\" without warranties of any kind. "
                  "You are solely responsible for the accuracy and legality of any data you upload. "
                  "All rights, title, and interest in all uploaded content remain with the creator and/or the uploader. "
                  "The application operator is not liable for any loss, damage, or claims arising from use of the app "
                  "or generated reports. By continuing, you agree to these terms.",
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: accepted,
                      onChanged: (value) {
                        accepted = value ?? false;
                        (context as Element).markNeedsBuild();
                      },
                    ),
                    Expanded(child: Text(t(context, "terms_accept"))),
                  ],
                ),
              ],
            ),
          ),
        ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t(context, "terms_decline_button")),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(accepted),
              child: Text(t(context, "terms_accept_button")),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<String?> _promptForCode() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(context, "verification_code_title")),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: t(context, "verification_code_label")),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(t(context, "cancel_button")),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(t(context, "verify_code_button")),
          ),
        ],
      ),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t(context, "login_title")), actions: appBarActions(context)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: phoneController,
              textDirection: _textDirection(context),
              textAlign: _textAlign(context),
              decoration: InputDecoration(labelText: t(context, "phone_label")),
            ),
            TextField(
              controller: emailController,
              readOnly: !emailEditable,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              decoration: InputDecoration(labelText: t(context, "email_label")),
            ),
            TextField(
              controller: passwordController,
              textDirection: _textDirection(context),
              textAlign: _textAlign(context),
              decoration: InputDecoration(labelText: t(context, "password_label")),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: loading ? null : _auth,
              child: Text(t(context, "login_button")),
            ),
          ],
        ),
      ),
    );
  }
}

class StartReportScreen extends StatefulWidget {
  const StartReportScreen({super.key});

  @override
  State<StartReportScreen> createState() => _StartReportScreenState();
}

class _StartReportScreenState extends State<StartReportScreen> {
  final locationController = TextEditingController();
  String? error;
  List<TemplateInfo> templates = [];
  String? selectedTemplateKey;
  List<String> recentLocations = [];
  List<String> locationHistory = [];
  bool loading = false;
  @override
  void initState() {
    super.initState();
    _loadTemplates();
    _loadLocations();
    _loadLocationHistory();
  }

  Future<void> _loadTemplates() async {
    try {
      final list = await api.listTemplates();
      if (mounted) {
        setState(() {
          templates = list;
          selectedTemplateKey = list.isNotEmpty ? list.first.key : null;
        });
      }
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _loadLocations() async {
    try {
      final list = await api.listLocations();
      if (mounted) {
        final cleaned = list.map(HistoryStore.normalizeValue).where((e) => e.isNotEmpty).toList();
        setState(() => recentLocations = cleaned);
      }
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _loadLocationHistory() async {
    final list = await HistoryStore.getHistory("history_locations", userKey: currentUserKey.value);
    if (mounted) {
      setState(() => locationHistory = list);
    }
  }

  Future<ActiveSessionData?> _getActiveSession() async {
    try {
      return await api.getActiveSession();
    } catch (_) {
      return null;
    }
  }

  Future<void> _start() async {
    try {
      final existing = await _getActiveSession();
      if (existing != null) {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ContactsScreen(
                initialLocation: existing.location,
                templateKey: existing.templateKey,
                templateTitle: existing.title,
              ),
            ),
          );
        }
        return;
      }
      if (selectedTemplateKey == null) {
        setState(() => error = t(context, "error_no_template"));
        return;
      }
      final templateTitle = templates
          .firstWhere((t) => t.key == selectedTemplateKey, orElse: () => templates.first)
          .title;
      await HistoryStore.addValue(
        "history_locations",
        locationController.text,
        userKey: currentUserKey.value,
      );
      await api.startReport(locationController.text.trim(), selectedTemplateKey!);
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ContactsScreen(
              initialLocation: locationController.text.trim(),
              templateKey: selectedTemplateKey!,
              templateTitle: templateTitle,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, "start_report_title")),
        actions: appBarActions(context, showLogout: true),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Autocomplete<String>(
              optionsBuilder: (value) {
                final allLocations = {...recentLocations, ...locationHistory}.toList();
                if (value.text.isEmpty) {
                  return allLocations;
                }
                return allLocations.where(
                  (option) => option.toLowerCase().contains(value.text.toLowerCase()),
                );
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                controller.text = locationController.text;
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: controller.text.length),
                );
                controller.addListener(() {
                  locationController.text = controller.text;
                });
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textDirection: _textDirection(context),
                  textAlign: _textAlign(context),
                  decoration: InputDecoration(labelText: t(context, "location_label")),
                );
              },
            ),
            if (recentLocations.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  "${t(context, "saved_locations_label")}: ${recentLocations.join(", ")}",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            if (templates.isNotEmpty)
              DropdownButtonFormField<String>(
                value: selectedTemplateKey,
                decoration: InputDecoration(labelText: t(context, "template_label")),
                items: templates
                    .map((t) => DropdownMenuItem(
                          value: t.key,
                          enabled: t.key == "INSPECTION_REPORT",
                          child: Text(
                            t.title,
                            style: t.key == "INSPECTION_REPORT"
                                ? null
                                : TextStyle(color: Theme.of(context).disabledColor),
                          ),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => selectedTemplateKey = value),
              ),
            const SizedBox(height: 16),
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(onPressed: _start, child: Text(t(context, "start_button"))),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RecentReportsScreen()),
              ),
              child: Text(t(context, "recent_reports_button")),
            ),
          ],
        ),
      ),
    );
  }
}

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({
    super.key,
    required this.initialLocation,
    required this.templateKey,
    required this.templateTitle,
  });

  final String initialLocation;
  final String templateKey;
  final String templateTitle;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<ContactInfo> contacts = [];
  final Set<String> attendees = {};
  final Set<String> distribution = {};
  String? error;
  bool loading = false;

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  List<String> nameHistory = [];
  List<String> emailHistory = [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _loadHistory();
    _loadExistingSelection();
  }

  Future<void> _loadContacts() async {
    try {
      final list = await api.listContacts();
      if (mounted) {
        setState(() => contacts = list);
      }
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _loadHistory() async {
    final names = await HistoryStore.getHistory("history_contact_names", userKey: currentUserKey.value);
    final emails = await HistoryStore.getHistory("history_contact_emails", userKey: currentUserKey.value);
    if (mounted) {
      setState(() {
        nameHistory = names;
        emailHistory = emails;
      });
    }
  }

  Future<void> _loadExistingSelection() async {
    try {
      final session = await api.getActiveSession();
      if (!mounted) return;
      setState(() {
        attendees
          ..clear()
          ..addAll(session.attendees);
        distribution
          ..clear()
          ..addAll(session.distributionList);
      });
    } catch (_) {}
  }

  bool _isValidEmail(String value) {
    final email = value.trim();
    if (email.isEmpty) return false;
    final asciiOnly = RegExp(r"^[\x00-\x7F]+$");
    final pattern = RegExp(r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$");
    return asciiOnly.hasMatch(email) && pattern.hasMatch(email);
  }

  Future<void> _addContact() async {
    try {
      final name = nameController.text.trim();
      final email = emailController.text.trim();
      if (name.isEmpty || email.isEmpty) {
        setState(() => error = t(context, "error_name_email_required"));
        return;
      }
      if (!_isValidEmail(email)) {
        setState(() => error = t(context, "error_email_invalid"));
        return;
      }
      final contact = await api.addContact(name: name, email: email);
      await HistoryStore.addValue("history_contact_names", name, userKey: currentUserKey.value);
      await HistoryStore.addValue("history_contact_emails", email, userKey: currentUserKey.value);
      setState(() {
        contacts.add(contact);
        nameController.clear();
        emailController.clear();
      });
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _pickFromPhone() async {
    final permitted = await FlutterContacts.requestPermission();
    if (!permitted) {
      setState(() => error = t(context, "contacts_permission_denied"));
      return;
    }
    final phoneContacts = await FlutterContacts.getContacts(withProperties: true);
    if (phoneContacts.isEmpty) {
      setState(() => error = t(context, "contacts_empty_phone"));
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final searchController = TextEditingController();
        List<Contact> filtered = List.from(phoneContacts);
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            void filter(String q) {
              setStateSheet(() {
                filtered = phoneContacts
                    .where((c) => c.displayName.toLowerCase().contains(q.toLowerCase()))
                    .toList();
              });
            }

            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    textDirection: _textDirection(context),
                    textAlign: _textAlign(context),
                    decoration: InputDecoration(labelText: t(context, "search_contacts_label")),
                    onChanged: filter,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final c = filtered[index];
                        final email = c.emails.isNotEmpty ? c.emails.first.address : "";
                        return ListTile(
                          title: Text(c.displayName),
                          subtitle: Text(email),
                          onTap: () {
                            nameController.text = c.displayName;
                            if (email.isNotEmpty) {
                              emailController.text = email;
                            }
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _continue() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await api.setReportContacts(
        attendees: attendees.toList(),
        distributionList: distribution.toList(),
      );
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AddItemScreen(
              location: widget.initialLocation,
              templateTitle: widget.templateTitle,
            ),
          ),
        );
      }
    } catch (e) {
      final message = e.toString();
      if (message.contains("No active report")) {
        try {
          await api.startReport(widget.initialLocation, widget.templateKey);
          await api.setReportContacts(
            attendees: attendees.toList(),
            distributionList: distribution.toList(),
          );
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AddItemScreen(
                  location: widget.initialLocation,
                  templateTitle: widget.templateTitle,
                ),
              ),
            );
          }
          return;
        } catch (inner) {
          setState(() => error = inner.toString());
        }
      } else {
        setState(() => error = message);
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, "contacts_title")),
        actions: appBarActions(context, showLogout: true),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            Autocomplete<String>(
              optionsBuilder: (value) {
                if (value.text.isEmpty) {
                  return nameHistory;
                }
                return nameHistory.where(
                  (option) => option.toLowerCase().contains(value.text.toLowerCase()),
                );
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                controller.text = nameController.text;
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: controller.text.length),
                );
                controller.addListener(() {
                  nameController.text = controller.text;
                });
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textDirection: _textDirection(context),
                  textAlign: _textAlign(context),
                  decoration: InputDecoration(labelText: t(context, "name_label")),
                );
              },
            ),
            Autocomplete<String>(
              optionsBuilder: (value) {
                if (value.text.isEmpty) {
                  return emailHistory;
                }
                return emailHistory.where(
                  (option) => option.toLowerCase().contains(value.text.toLowerCase()),
                );
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                controller.text = emailController.text;
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: controller.text.length),
                );
                controller.addListener(() {
                  emailController.text = controller.text;
                });
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  decoration: InputDecoration(labelText: t(context, "email_label")),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(onPressed: _addContact, child: Text(t(context, "add_contact_button"))),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _pickFromPhone, child: Text(t(context, "pick_from_phone_button"))),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: contacts.length,
                itemBuilder: (context, index) {
                  final c = contacts[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${c.name} (${c.email})"),
                          Row(
                            children: [
                              Expanded(
                                child: CheckboxListTile(
                                  title: Text(t(context, "attendee_label")),
                                  value: attendees.contains(c.id),
                                  onChanged: (value) {
                                    setState(() {
                                      if (value == true) {
                                        attendees.add(c.id);
                                      } else {
                                        attendees.remove(c.id);
                                      }
                                    });
                                  },
                                ),
                              ),
                              Expanded(
                                child: CheckboxListTile(
                                  title: Text(t(context, "recipient_label")),
                                  value: distribution.contains(c.id),
                                  onChanged: (value) {
                                    setState(() {
                                      if (value == true) {
                                        distribution.add(c.id);
                                      } else {
                                        distribution.remove(c.id);
                                      }
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: loading ? null : _continue,
              child: Text(t(context, "continue_button")),
            ),
          ],
        ),
      ),
    );
  }
}

class RecentReportsScreen extends StatefulWidget {
  const RecentReportsScreen({super.key});

  @override
  State<RecentReportsScreen> createState() => _RecentReportsScreenState();
}

class _RecentReportsScreenState extends State<RecentReportsScreen> {
  List<ReportSummary> reports = [];
  String? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    try {
      final list = await api.listRecentReports();
      if (mounted) {
        setState(() => reports = list);
      }
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _openForEdit(ReportSummary report) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await api.openReport(report.reportId);
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AddItemScreen(
              location: report.location,
              templateTitle: report.title,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _organize(ReportSummary report) async {
    final folderController = TextEditingController(text: report.folder);
    final tagsController = TextEditingController(text: report.tags.join(", "));
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(context, "organize_report_button")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: folderController,
              textDirection: _textDirection(context),
              textAlign: _textAlign(context),
              decoration: InputDecoration(labelText: t(context, "folder_label")),
            ),
            TextField(
              controller: tagsController,
              textDirection: _textDirection(context),
              textAlign: _textAlign(context),
              decoration: InputDecoration(labelText: t(context, "tags_label")),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(context, "cancel_button")),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t(context, "save_button")),
          ),
        ],
      ),
    );
    if (result != true) return;
    final tags = tagsController.text
        .split(",")
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    await api.organizeReport(report.reportId, folderController.text.trim(), tags);
    await _loadReports();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, "recent_reports_title")),
        actions: appBarActions(context, showLogout: true),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            if (reports.isEmpty)
              Text(t(context, "no_reports_yet"))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: reports.length,
                  itemBuilder: (context, index) {
                    final r = reports[index];
                    final subtitleParts = <String>[
                      r.createdAt,
                      if (r.location.isNotEmpty) r.location,
                      if (r.folder.isNotEmpty) "📁 ${r.folder}",
                      if (r.tags.isNotEmpty) "🏷 ${r.tags.join(", ")}",
                    ];
                    return Card(
                      child: ListTile(
                        title: Text(r.title),
                        subtitle: Text(subtitleParts.join(" • ")),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: loading ? null : () => _openForEdit(r),
                              tooltip: t(context, "edit_report_button"),
                            ),
                            IconButton(
                              icon: const Icon(Icons.folder),
                              onPressed: loading ? null : () => _organize(r),
                              tooltip: t(context, "organize_report_button"),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AddItemScreen extends StatefulWidget {
  const AddItemScreen({super.key, this.location, this.templateTitle});

  final String? location;
  final String? templateTitle;

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final descriptionController = TextEditingController();
  final notesController = TextEditingController();
  File? photo;
  String? currentItemId;
  String? activeItemId;
  String? error;
  final stt.SpeechToText speech = stt.SpeechToText();
  final AudioRecorder audioRecorder = AudioRecorder();
  bool isRecording = false;
  String lastTranscript = "";
  String? recordingItemId;
  String? lastRecordingPath;
  List<String> descriptionHistory = [];
  List<String> notesHistory = [];
  List<ReportItemData> existingItems = [];
  String? editingItemId;
  String? speechLocaleId;
  Map<String, List<ReportPhotoData>> itemPhotos = {};
  Map<String, String> itemAudioPaths = {};
  String? sessionLocation;
  String? sessionTitle;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadExistingItems();
  }

  @override
  void dispose() {
    audioRecorder.dispose();
    descriptionController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    if (mounted) {
      setState(() {
        descriptionHistory = [];
        notesHistory = [];
      });
    }
  }

  Future<void> _loadExistingItems() async {
    try {
      final session = await api.getActiveSession();
      final grouped = <String, List<ReportPhotoData>>{};
      for (final photo in session.photos) {
        if (photo.itemId == null) continue;
        grouped.putIfAbsent(photo.itemId!, () => []).add(photo);
      }
      if (mounted) {
        setState(() {
          existingItems = session.items;
          itemPhotos = grouped;
          sessionLocation = session.location;
          sessionTitle = session.title;
          if (activeItemId != null && session.items.every((item) => item.id != activeItemId)) {
            activeItemId = null;
          }
        });
      }
    } catch (_) {}
  }

  Future<String?> _resolveSpeechLocale() async {
    try {
      final lang = Localizations.localeOf(context).languageCode.toLowerCase();
      final locales = await speech.locales();
      if (locales.isEmpty) return null;
      final match = locales.firstWhere(
        (l) => l.localeId.toLowerCase().startsWith(lang),
        orElse: () => locales.first,
      );
      return match.localeId;
    } catch (_) {
      return null;
    }
  }


  Future<bool> _savePhotoToGallery(String path) async {
    if (kIsWeb) return false;
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) return false;
      await PhotoManager.editor.saveImageWithPath(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _backupPhotoToDevice(String path) async {
    if (kIsWeb) return;
    try {
      // Android emulator/device path maps to: /data/data/<package>/app_flutter/...
      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory("${dir.path}/photo_backups");
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      final dotIndex = path.lastIndexOf(".");
      final ext = dotIndex == -1 ? "" : path.substring(dotIndex);
      final filename = "photo_${DateTime.now().millisecondsSinceEpoch}$ext";
      await File(path).copy("${backupDir.path}/$filename");
    } catch (_) {}
  }

  void _cleanupTempMedia(String path) {
    if (kIsWeb) return;
    try {
      final file = File(path);
      final name = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : "";
      final parent = file.parent.path;
      if (name.startsWith("res_timestamp") &&
          parent.endsWith("${Platform.pathSeparator}app_flutter")) {
        file.deleteSync();
      }
    } catch (_) {}
  }

  Future<void> _startAudioBackup() async {
    if (kIsWeb) return;
    try {
      // Android emulator/device path maps to: /data/data/<package>/app_flutter/...
      final dir = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory("${dir.path}/recordings");
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }
      final filename = "recording_${DateTime.now().millisecondsSinceEpoch}.m4a";
      final path = "${recordingsDir.path}/$filename";
      final hasPerm = await audioRecorder.hasPermission();
      if (!hasPerm) return;
      await audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      setState(() => lastRecordingPath = null);
    } catch (_) {}
  }

  Future<String?> _stopAudioBackup() async {
    if (kIsWeb) return null;
    try {
      final path = await audioRecorder.stop();
      if (path != null && mounted) {
        setState(() => lastRecordingPath = path);
      }
      return path;
    } catch (_) {}
    return null;
  }

  Widget _buildAttachments() {
    if (activeItemId == null) return const SizedBox.shrink();
    final photos = itemPhotos[activeItemId] ?? [];
    final audioPath = itemAudioPaths[activeItemId];
    if (photos.isEmpty && audioPath == null) {
      return const SizedBox.shrink();
    }
    final headers = api.token != null ? {"Authorization": "Bearer ${api.token}"} : <String, String>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(t(context, "attached_media_label")),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final photo = photos[index];
                final url = "$apiBaseUrl/reports/photo/${photo.id}";
                return ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    url,
                    headers: headers,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 80,
                        height: 80,
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
        if (audioPath != null) ...[
          const SizedBox(height: 6),
          Text("${t(context, "attached_audio_label")}: $audioPath"),
        ],
      ],
    );
  }

  ReportItemData? _findItem(String itemId) {
    for (final item in existingItems) {
      if (item.id == itemId) return item;
    }
    return null;
  }

  Future<void> _applyTranscriptToItem(String itemId, String transcript) async {
    final item = _findItem(itemId);
    if (item == null) {
      setState(() => error = t(context, "transcription_error"));
      return;
    }
    final newNotes = item.notes.isEmpty ? transcript : "${item.notes}\n$transcript";
    await api.updateItem(itemId, item.description, newNotes);
    await _loadExistingItems();
  }

  Future<bool> _createItemFromDraftForMedia() async {
    final descriptionTrimmed = descriptionController.text.trim();
    final notesTrimmed = notesController.text.trim();
    if (descriptionTrimmed.isEmpty && notesTrimmed.isEmpty) {
      return false;
    }
    if (descriptionTrimmed.isEmpty && notesTrimmed.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t(context, "confirm_notes_only_title")),
          content: Text(t(context, "confirm_notes_only_body")),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t(context, "confirm_notes_only_no")),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t(context, "confirm_notes_only_yes")),
            ),
          ],
        ),
      );
      if (proceed != true) {
        return false;
      }
    }
    final id = await api.addItem(descriptionTrimmed, notesTrimmed);
    setState(() {
      currentItemId = id;
      activeItemId = id;
      editingItemId = id;
    });
    await _loadExistingItems();
    return true;
  }

  Future<String?> _promptForItemSelection() async {
    if (existingItems.isEmpty) return null;
    if (!mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(t(context, "select_item_title")),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: existingItems.length,
                  itemBuilder: (context, index) {
                    final item = existingItems[index];
                    final label = item.description.isNotEmpty
                        ? item.description
                        : (item.notes.isNotEmpty ? item.notes : item.number);
                    return ListTile(
                      title: Text("${item.number}  $label"),
                      onTap: () => Navigator.of(context).pop(item.id),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _ensureActiveItemForMedia() async {
    if (activeItemId != null) return true;
    final descriptionTrimmed = descriptionController.text.trim();
    final notesTrimmed = notesController.text.trim();
    if (descriptionTrimmed.isNotEmpty || notesTrimmed.isNotEmpty) {
      return await _createItemFromDraftForMedia();
    }
    final selected = await _promptForItemSelection();
    if (selected != null) {
      setState(() => activeItemId = selected);
      return true;
    }
    setState(() => error = t(context, "error_photo_needs_item"));
    return false;
  }

  Future<void> _addItem() async {
    try {
      final descriptionTrimmed = descriptionController.text.trim();
      final notesTrimmed = notesController.text.trim();
      if (descriptionTrimmed.isEmpty && notesTrimmed.isEmpty) {
        setState(() => error = t(context, "error_item_empty"));
        return;
      }
      if (descriptionTrimmed.isEmpty && notesTrimmed.isNotEmpty) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t(context, "confirm_notes_only_title")),
            content: Text(t(context, "confirm_notes_only_body")),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t(context, "confirm_notes_only_no")),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(t(context, "confirm_notes_only_yes")),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
      if (editingItemId != null) {
        await api.updateItem(
          editingItemId!,
          descriptionTrimmed,
          notesTrimmed,
        );
        setState(() {
          editingItemId = null;
          descriptionController.clear();
          notesController.clear();
          lastTranscript = "";
          lastRecordingPath = null;
        });
        await _loadExistingItems();
        return;
      }
      final id = await api.addItem(
        descriptionTrimmed,
        notesTrimmed,
      );
      setState(() {
        currentItemId = id;
        activeItemId = null;
        descriptionController.clear();
        notesController.clear();
        lastTranscript = "";
        lastRecordingPath = null;
      });
      await _loadExistingItems();
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _takePhoto() async {
    if (!await _ensureActiveItemForMedia()) {
      return;
    }
    final camOk = await Permission.camera.request();
    if (!camOk.isGranted) {
      setState(() => error = t(context, "permission_camera_denied"));
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera);
    if (picked != null) {
      setState(() => photo = File(picked.path));
      final saved = await _savePhotoToGallery(picked.path);
      if (!saved) {
        await _backupPhotoToDevice(picked.path);
      }
      _cleanupTempMedia(picked.path);
      await _uploadPhotoFile(File(picked.path), activeItemId!);
    }
  }

  Future<void> _takePhotoForItem(String itemId) async {
    final camOk = await Permission.camera.request();
    if (!camOk.isGranted) {
      setState(() => error = t(context, "permission_camera_denied"));
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera);
    if (picked == null) return;
    try {
      final saved = await _savePhotoToGallery(picked.path);
      if (!saved) {
        await _backupPhotoToDevice(picked.path);
      }
      _cleanupTempMedia(picked.path);
      await api.uploadPhoto(File(picked.path), itemId: itemId);
      await _loadExistingItems();
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _uploadPhoto() async {
    if (!await _ensureActiveItemForMedia()) {
      return;
    }
    final photosOk = await Permission.photos.request();
    if (!photosOk.isGranted) {
      setState(() => error = t(context, "permission_photos_denied"));
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final saved = await _savePhotoToGallery(picked.path);
    if (!saved) {
      await _backupPhotoToDevice(picked.path);
    }
    _cleanupTempMedia(picked.path);
    await _uploadPhotoFile(File(picked.path), activeItemId!);
  }

  Future<void> _uploadPhotoFile(File file, String itemId) async {
    try {
      await api.uploadPhoto(file, itemId: itemId);
      if (mounted) {
        setState(() => photo = null);
      }
      await _loadExistingItems();
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _finalize() async {
    try {
      final committed = await _commitDraftItemBeforeFinalize();
      if (!committed) return;
      if (existingItems.isEmpty) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t(context, "confirm_empty_report_title")),
            content: Text(t(context, "confirm_empty_report_body")),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t(context, "confirm_empty_report_no")),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(t(context, "confirm_empty_report_yes")),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
      final now = DateTime.now();
      final datePart =
          "${now.year.toString().padLeft(4, "0")}${now.month.toString().padLeft(2, "0")}${now.day.toString().padLeft(2, "0")}";
      final timePart =
          "${now.hour.toString().padLeft(2, "0")}${now.minute.toString().padLeft(2, "0")}";
      final templatePart =
          _safeFilePart(widget.templateTitle ?? sessionTitle ?? t(context, "add_item_title"));
      final locationPart = _safeFilePart(widget.location ?? sessionLocation ?? "");
      final filenameParts = [
        if (templatePart.isNotEmpty) templatePart,
        if (locationPart.isNotEmpty) locationPart,
        "$datePart-$timePart",
      ];
      final filename = filenameParts.join("_");
      final path = await api.finalizeAndSave(filename: filename);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => DoneScreen(filePath: path)),
        );
      }
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _cancelReport() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(context, "cancel_report_title")),
        content: Text(t(context, "cancel_report_body")),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(context, "cancel_button")),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t(context, "cancel_report_confirm")),
          ),
        ],
      ),
    );
    if (proceed != true) return;
    try {
      await api.cancelReport();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const StartReportScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<bool> _commitDraftItemBeforeFinalize() async {
    String description = descriptionController.text.trim();
    String notes = notesController.text.trim();
    if (description.isEmpty && notes.isEmpty) {
      return true;
    }
    if (description.isEmpty && notes.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t(context, "confirm_notes_only_title")),
          content: Text(t(context, "confirm_notes_only_body")),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t(context, "confirm_notes_only_no")),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t(context, "confirm_notes_only_yes")),
            ),
          ],
        ),
      );
      if (proceed != true) {
        return false;
      }
    }
    if (editingItemId != null) {
      await api.updateItem(editingItemId!, description, notes);
      setState(() {
        editingItemId = null;
        descriptionController.clear();
        notesController.clear();
      });
      await _loadExistingItems();
      return true;
    }
    final id = await api.addItem(description, notes);
    setState(() {
      currentItemId = id;
      activeItemId = id;
      descriptionController.clear();
      notesController.clear();
    });
    await _loadExistingItems();
    return true;
  }

  Future<void> _toggleRecording({String? targetItemId}) async {
    try {
      if (!isRecording) {
        final micOk = await Permission.microphone.request();
        if (!micOk.isGranted) {
          setState(() => error = t(context, "transcription_error"));
          return;
        }
        await _startAudioBackup();
        final available = await speech.initialize(
          onError: (err) {
            if (mounted) {
              setState(() => error = "${t(context, "transcription_error")} (${err.errorMsg})");
            }
          },
        );
        if (!available) {
          setState(() => error = t(context, "transcription_error"));
          return;
        }
        speechLocaleId ??= await _resolveSpeechLocale();
        setState(() {
          isRecording = true;
          lastTranscript = "";
          recordingItemId = targetItemId;
        });
        await speech.listen(
          localeId: speechLocaleId,
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          onResult: (result) {
            setState(() {
              lastTranscript = result.recognizedWords;
              if (recordingItemId == null) {
                descriptionController.text = lastTranscript;
                descriptionController.selection = TextSelection.fromPosition(
                  TextPosition(offset: descriptionController.text.length),
                );
              }
            });
          },
        );
      } else {
        await speech.stop();
        final audioPath = await _stopAudioBackup();
        final target = recordingItemId;
        setState(() {
          isRecording = false;
          recordingItemId = null;
        });
        if (target != null && lastTranscript.isNotEmpty) {
          await _applyTranscriptToItem(target, lastTranscript);
        }
        if (target != null && audioPath != null) {
          setState(() => itemAudioPaths[target] = audioPath);
        }
      }
    } catch (_) {
      setState(() => error = t(context, "transcription_error"));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, "add_item_title")),
        actions: appBarActions(
          context,
          showLogout: true,
          showCancelReport: true,
          onSelected: (value) {
            if (value == "cancel_report") {
              _cancelReport();
            }
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
            if (existingItems.isNotEmpty)
              SizedBox(
                height: 120,
                child: ListView.builder(
                  itemCount: existingItems.length,
                  itemBuilder: (context, index) {
                    final item = existingItems[index];
                    return ListTile(
                      title: Text("${item.number}. ${item.description}"),
                      subtitle: Text(item.notes),
                      selected: item.id == activeItemId,
                      selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                      onTap: () {
                        setState(() {
                          activeItemId = item.id;
                          currentItemId = item.id;
                          editingItemId = item.id;
                          descriptionController.text = item.description;
                          notesController.text = item.notes;
                        });
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.photo_camera),
                            onPressed: () => _takePhotoForItem(item.id),
                          ),
                          IconButton(
                            icon: Icon(isRecording && recordingItemId == item.id ? Icons.stop : Icons.mic),
                            onPressed: isRecording && recordingItemId != item.id
                                ? null
                                : () => _toggleRecording(targetItemId: item.id),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () {
                              setState(() {
                                activeItemId = item.id;
                                currentItemId = item.id;
                                editingItemId = item.id;
                                descriptionController.text = item.description;
                                notesController.text = item.notes;
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            Autocomplete<String>(
              optionsBuilder: (value) {
                if (value.text.isEmpty) {
                  return descriptionHistory;
                }
                return descriptionHistory.where(
                  (option) => option.toLowerCase().contains(value.text.toLowerCase()),
                );
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                controller.text = descriptionController.text;
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: controller.text.length),
                );
                controller.addListener(() {
                  descriptionController.text = controller.text;
                });
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textDirection: _textDirection(context),
                  textAlign: _textAlign(context),
                  decoration: InputDecoration(labelText: t(context, "description_label")),
                );
              },
            ),
            Autocomplete<String>(
              optionsBuilder: (value) {
                if (value.text.isEmpty) {
                  return notesHistory;
                }
                return notesHistory.where(
                  (option) => option.toLowerCase().contains(value.text.toLowerCase()),
                );
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                controller.text = notesController.text;
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: controller.text.length),
                );
                controller.addListener(() {
                  notesController.text = controller.text;
                });
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textDirection: _textDirection(context),
                  textAlign: _textAlign(context),
                  decoration: InputDecoration(labelText: t(context, "notes_label")),
                );
              },
            ),
            _buildAttachments(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: t(context, "take_photo_button"),
                    child: ElevatedButton(
                      onPressed: _takePhoto,
                      child: const Icon(Icons.photo_camera),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Tooltip(
                    message: t(context, "upload_photo_button"),
                    child: OutlinedButton(
                      onPressed: _uploadPhoto,
                      child: const Icon(Icons.photo_library),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _toggleRecording(),
              child: Icon(isRecording ? Icons.stop : Icons.mic),
            ),
            if (lastTranscript.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text("${t(context, "transcription_label")}: $lastTranscript"),
              ),
            if (lastRecordingPath != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text("${t(context, "audio_saved_label")}: $lastRecordingPath"),
              ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _addItem, child: Text(t(context, "add_item_button"))),
            const SizedBox(height: 12),
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _finalize, child: Text(t(context, "generate_report_button"))),
          ],
      ),
    );
  }
}

class DoneScreen extends StatelessWidget {
  const DoneScreen({super.key, required this.filePath});

  final String filePath;

  Future<void> _openFile() async {
    await OpenFilex.open(filePath);
  }

  Future<void> _shareFile() async {
    await Share.shareXFiles([XFile(filePath)]);
  }

  Future<void> _saveToDownloads(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }
    try {
      final storageOk = await Permission.storage.request();
      if (!storageOk.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context, "permission_storage_denied"))),
        );
        return;
      }
      final filename = filePath.split(Platform.pathSeparator).last;
      final primary = Directory("/storage/emulated/0/Download");
      final fallback = Directory("/sdcard/Download");
      final downloadsDir = await primary.exists() ? primary : fallback;
      if (!await downloadsDir.exists()) {
        throw Exception("Downloads not found");
      }
      final targetPath = "${downloadsDir.path}/$filename";
      await File(filePath).copy(targetPath);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, "report_saved_downloads"))),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, "report_save_failed"))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, "done_title")),
        actions: appBarActions(context, showLogout: true),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t(context, "report_generated")),
            const SizedBox(height: 8),
            Text(filePath, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _openFile,
              child: Text(t(context, "open_report_button")),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _shareFile,
              child: Text(t(context, "share_report_button")),
            ),
            if (!kIsWeb && Platform.isAndroid) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _saveToDownloads(context),
                child: Text(t(context, "save_downloads_button")),
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const StartReportScreen()),
              ),
              child: Text(t(context, "new_report_button")),
            ),
          ],
        ),
      ),
    );
  }
}
