import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_screen.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'history_screen.dart';
import 'nearby_requests_screen.dart';

const String baseUrl = "http://192.168.100.53:8000";

const List<String> kBloodTypes = [
  "O-",
  "O+",
  "A-",
  "A+",
  "B-",
  "B+",
  "AB-",
  "AB+",
];

const List<String> kKnownHospitals = [
  "Aga Khan University Hospital, Karachi",
  "Jinnah Postgraduate Medical Centre, Karachi",
  "Liaquat National Hospital, Karachi",
  "Civil Hospital Karachi",
  "South City Hospital, Karachi",
  "Shifa International Hospital, Islamabad",
  "Pakistan Institute of Medical Sciences (PIMS), Islamabad",
  "Holy Family Hospital, Rawalpindi",
  "Combined Military Hospital (CMH), Rawalpindi",
  "Services Hospital, Lahore",
  "Mayo Hospital, Lahore",
  "Jinnah Hospital, Lahore",
  "Shaukat Khanum Memorial Cancer Hospital, Lahore",
  "Nishtar Hospital, Multan",
  "Lady Reading Hospital, Peshawar",
  "Hayatabad Medical Complex, Peshawar",
  "Ghurki Trust Teaching Hospital, Lahore",
];

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final prefs = await SharedPreferences.getInstance();
  final storedToken = prefs.getString("access_token");
  runApp(BloodApp(initialToken: storedToken));
}

class BloodApp extends StatelessWidget {
  final String? initialToken;
  const BloodApp({super.key, this.initialToken});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFC62828),
      brightness: Brightness.light,
    );

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Blood Response System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(fontWeight: FontWeight.w800),
          titleMedium: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      home: initialToken != null
          ? HomeScreen(token: initialToken!)
          : AuthScreen(
              onAuthenticated: (token, userId, phone) =>
                  HomeScreen(token: token),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------

class SectionCard extends StatelessWidget {
  final Widget child;
  const SectionCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );
  }
}

class BloodTypePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const BloodTypePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kBloodTypes.map((t) {
        final selected = t == value;
        return ChoiceChip(
          label: Text(
            t,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : scheme.primary,
            ),
          ),
          selected: selected,
          onSelected: (_) => onChanged(t),
          selectedColor: scheme.primary,
          backgroundColor: scheme.primary.withValues(alpha: 0.08),
          side: BorderSide.none,
          showCheckmark: false,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        );
      }).toList(),
    );
  }
}

class LabeledField extends StatelessWidget {
  final String label;
  const LabeledField({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home / Registration screen
// ---------------------------------------------------------------------------

// Ensure your constants and auxiliary widgets are imported or defined:
// const String baseUrl = "http://127.0.0.1:8000";

class HomeScreen extends StatefulWidget {
  final String token;
  const HomeScreen({super.key, required this.token});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? userId;
  String? registeredName;
  String token = "";
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  String bloodType = "O-";
  bool isLoading = false;

  // Donor availability state
  bool isDonorAvailable = true;
  bool availabilityLoading = false;

  @override
  void initState() {
    super.initState();
    token = widget.token;
    _fetchMe();

    // 1. Foreground Notification Toast
    FirebaseMessaging.onMessage.listen((message) {
      if (message.notification != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.black87,
            content: Text(
              "${message.notification!.title}: ${message.notification!.body}",
            ),
          ),
        );
      }
    });

    // 2. Background Notification Tap (App minimized/alive in memory)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      await _navigateToNearbyWhenReady();
    });

    // 3. Cold Start Notification Tap (App fully terminated)
    FirebaseMessaging.instance.getInitialMessage().then((
      RemoteMessage? message,
    ) async {
      if (message != null) {
        await _navigateToNearbyWhenReady();
      }
    });
  }

  // Helper method to await user profile loading before navigating
  Future<void> _navigateToNearbyWhenReady() async {
    for (int i = 0; i < 10 && userId == null; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (userId != null && navigatorKey.currentState != null) {
      navigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => NearbyRequestsScreen(token: token, donorId: userId!),
        ),
      );
    }
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchMe() async {
    try {
      final res = await http.get(
        Uri.parse("$baseUrl/users/me"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          userId = data["id"];
          registeredName = data["full_name"];
          bloodType = data["blood_type"];
          isDonorAvailable = data["is_donor_available"] ?? true;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleAvailability(bool value) async {
    setState(() => availabilityLoading = true);
    try {
      final res = await http.patch(
        Uri.parse("$baseUrl/users/me/availability"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"is_donor_available": value}),
      );
      if (res.statusCode == 200) {
        setState(() => isDonorAvailable = value);
        _showSnack(
          value
              ? "You're marked as available to donate."
              : "You're paused — you won't be notified.",
        );
      } else {
        _showSnack("Failed to update availability: ${res.body}");
      }
    } catch (e) {
      _showSnack("Connection error: $e");
    } finally {
      setState(() => availabilityLoading = false);
    }
  }

  Future<Position> _getLocation() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return Geolocator.getCurrentPosition();
  }

  Future<String?> _getFcmToken() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> _registerUser() async {
    if (nameCtrl.text.trim().isEmpty || phoneCtrl.text.trim().isEmpty) {
      _showSnack("Please fill in your name and phone number.");
      return;
    }

    setState(() => isLoading = true);
    try {
      final pos = await _getLocation();
      final fcmToken = await _getFcmToken();

      final res = await http.post(
        Uri.parse("$baseUrl/users/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone_number": phoneCtrl.text.trim(),
          "full_name": nameCtrl.text.trim(),
          "blood_type": bloodType,
          "latitude": pos.latitude,
          "longitude": pos.longitude,
          "fcm_token": fcmToken,
        }),
      );

      if (res.statusCode == 201) {
        final data = jsonDecode(res.body);
        setState(() {
          userId = data["id"];
          registeredName = nameCtrl.text.trim();
          isDonorAvailable = data["is_donor_available"] ?? true;
          if (data["access_token"] != null) {
            token = data["access_token"];
          }
        });

        if (data["access_token"] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString("access_token", data["access_token"]);
        }

        _showSnack("You're registered as a $bloodType donor.");
      }
    } catch (e) {
      _showSnack("Connection error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.bloodtype, color: Colors.white),
            SizedBox(width: 8),
            Text("Blood Response"),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: "My activity",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => HistoryScreen(token: token)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Log out",
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (_) => AuthScreen(
                    onAuthenticated: (token, userId, phone) =>
                        HomeScreen(token: token),
                  ),
                ),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Hero banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.favorite,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    "Connect urgent blood needs\nwith nearby donors, instantly.",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (userId != null) ...[
            // Registered User Details Card
            SectionCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: scheme.primary.withValues(alpha: 0.1),
                    child: Icon(Icons.check_circle, color: scheme.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Registered as $registeredName",
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          "Donor type: $bloodType",
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Availability Toggle Switch Card
            SectionCard(
              child: Row(
                children: [
                  Icon(
                    isDonorAvailable
                        ? Icons.notifications_active
                        : Icons.notifications_off,
                    color: isDonorAvailable ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Available to donate",
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          isDonorAvailable
                              ? "You'll be notified of nearby matching requests."
                              : "Paused — you won't receive notifications.",
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  availabilityLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Switch(
                          value: isDonorAvailable,
                          onChanged: _toggleAvailability,
                        ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CreateRequestScreen(requesterId: userId!, token: token),
                  ),
                ),
                icon: const Icon(Icons.emergency),
                label: const Text("Post an Urgent Blood Request"),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        NearbyRequestsScreen(token: token, donorId: userId!),
                  ),
                ),
                icon: const Icon(Icons.volunteer_activism),
                label: const Text("Browse Nearby Requests"),
              ),
            ),
            const SizedBox(height: 24),
            Divider(color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() {
                  userId = null;
                  registeredName = null;
                  nameCtrl.clear();
                  phoneCtrl.clear();
                }),
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text("Register a different donor"),
              ),
            ),
          ] else ...[
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Donor Registration",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Register once — we'll notify you when someone nearby needs your blood type.",
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  const LabeledField(label: "Full name"),
                  TextField(controller: nameCtrl),
                  const SizedBox(height: 16),
                  const LabeledField(label: "Phone number"),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: "+92 3XX XXXXXXX",
                    ),
                  ),
                  const SizedBox(height: 16),
                  const LabeledField(label: "Blood type"),
                  BloodTypePicker(
                    value: bloodType,
                    onChanged: (v) => setState(() => bloodType = v),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isLoading ? null : _registerUser,
                      icon: isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.person_add),
                      label: Text(
                        isLoading ? "Registering..." : "Register as Donor",
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Blood request + matches screen
// ---------------------------------------------------------------------------

class CreateRequestScreen extends StatefulWidget {
  final String requesterId;
  final String token;
  const CreateRequestScreen({
    super.key,
    required this.requesterId,
    required this.token,
  });

  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  final hospitalCtrl = TextEditingController();
  final unitsCtrl = TextEditingController(text: "1");
  String bloodType = "O-";
  String urgency = "critical";
  bool isSubmitting = false;

  @override
  void dispose() {
    hospitalCtrl.dispose();
    unitsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (hospitalCtrl.text.trim().isEmpty) {
      _showSnack("Enter a hospital name.");
      return;
    }

    setState(() => isSubmitting = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition();

      final res = await http.post(
        Uri.parse("$baseUrl/blood-requests/"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${widget.token}",
        },
        body: jsonEncode({
          "requester_id": widget.requesterId,
          "blood_type_needed": bloodType,
          "units_needed": int.tryParse(unitsCtrl.text) ?? 1,
          "hospital_name": hospitalCtrl.text.trim(),
          "latitude": pos.latitude,
          "longitude": pos.longitude,
          "urgency": urgency,
        }),
      );

      if (res.statusCode == 201) {
        final data = jsonDecode(res.body);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RequestResultsScreen(
              requestId: data["id"],
              hospitalName: data["hospital_name"],
              bloodTypeNeeded: data["blood_type_needed"],
              unitsNeeded: data["units_needed"],
              createdAt: data["created_at"],
              expiresAt: data["expires_at"],
              token: widget.token,
            ),
          ),
        );
      } else {
        _showSnack("Failed to create request: ${res.body}");
      }
    } catch (e) {
      _showSnack("Error: $e");
    } finally {
      setState(() => isSubmitting = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text("Urgent Blood Request")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LabeledField(label: "Hospital name"),
                Autocomplete<String>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty)
                      return const Iterable<String>.empty();
                    return kKnownHospitals.where(
                      (h) => h.toLowerCase().contains(
                        textEditingValue.text.toLowerCase(),
                      ),
                    );
                  },
                  onSelected: (String selection) =>
                      hospitalCtrl.text = selection,
                  fieldViewBuilder:
                      (context, controller, focusNode, onFieldSubmitted) {
                        controller.addListener(
                          () => hospitalCtrl.text = controller.text,
                        );
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: const InputDecoration(
                            hintText: "Start typing a hospital name...",
                          ),
                        );
                      },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(12),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (context, index) {
                              final option = options.elementAt(index);
                              return ListTile(
                                dense: true,
                                title: Text(
                                  option,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                onTap: () => onSelected(option),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 90,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const LabeledField(label: "Units"),
                          TextField(
                            controller: unitsCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const LabeledField(label: "Blood type needed"),
                          BloodTypePicker(
                            value: bloodType,
                            onChanged: (v) => setState(() => bloodType = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const LabeledField(label: "Urgency"),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text("Critical (6h)"),
                      selected: urgency == "critical",
                      onSelected: (_) => setState(() => urgency = "critical"),
                    ),
                    ChoiceChip(
                      label: const Text("Urgent (24h)"),
                      selected: urgency == "urgent",
                      onSelected: (_) => setState(() => urgency = "urgent"),
                    ),
                    ChoiceChip(
                      label: const Text("Planned (72h)"),
                      selected: urgency == "planned",
                      onSelected: (_) => setState(() => urgency = "planned"),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: isSubmitting ? null : _submitRequest,
                    icon: isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search),
                    label: Text(
                      isSubmitting
                          ? "Posting..."
                          : "Post Request & Find Donors",
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RequestResultsScreen extends StatefulWidget {
  final String requestId;
  final String hospitalName;
  final String bloodTypeNeeded;
  final int unitsNeeded;
  final String createdAt;
  final String? expiresAt;
  final String token;

  const RequestResultsScreen({
    super.key,
    required this.requestId,
    required this.hospitalName,
    required this.bloodTypeNeeded,
    required this.unitsNeeded,
    required this.createdAt,
    required this.expiresAt,
    required this.token,
  });

  @override
  State<RequestResultsScreen> createState() => _RequestResultsScreenState();
}

class _RequestResultsScreenState extends State<RequestResultsScreen> {
  List<dynamic> matches = [];
  Map<String, String> responsesState = {};
  double? hospitalLat;
  double? hospitalLng;
  bool isLoading = true;
  String status = "open";

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    setState(() => isLoading = true);
    try {
      final matchRes = await http.get(
        Uri.parse("$baseUrl/blood-requests/${widget.requestId}/matches"),
      );
      if (matchRes.statusCode == 200) {
        final data = jsonDecode(matchRes.body);
        setState(() {
          matches = data["matches"] ?? [];
          status = data["status"] ?? "open";
          hospitalLat = data["hospital_location"]?["latitude"];
          hospitalLng = data["hospital_location"]?["longitude"];
        });
      }
      await _fetchResponses();
    } catch (_) {
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchResponses() async {
    try {
      final res = await http.get(
        Uri.parse("$baseUrl/blood-requests/${widget.requestId}/responses"),
      );
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        final updated = <String, String>{};
        for (var item in data) {
          updated[item["donor_id"]] = item["status"];
        }
        setState(() => responsesState = updated);
      }
    } catch (_) {}
  }

  String _referenceCode() => widget.requestId.substring(0, 8).toUpperCase();

  String _timeAgo(String iso) {
    final posted = DateTime.tryParse(iso);
    if (posted == null) return "";
    final diff = DateTime.now().toUtc().difference(posted.toUtc());
    if (diff.inMinutes < 1) return "just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "${diff.inHours}h ago";
    return "${diff.inDays}d ago";
  }

  String _expiresIn() {
    if (widget.expiresAt == null) return "";
    final exp = DateTime.tryParse(widget.expiresAt!);
    if (exp == null) return "";
    final diff = exp.toUtc().difference(DateTime.now().toUtc());
    if (diff.isNegative) return "Expired";
    if (diff.inHours < 1) return "Expires in ${diff.inMinutes}m";
    return "Expires in ${diff.inHours}h";
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text("Request Results")),
      body: RefreshIndicator(
        onRefresh: _loadMatches,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.hospitalName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              "${widget.bloodTypeNeeded} · ${widget.unitsNeeded} unit(s) · Ref #${_referenceCode()}",
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Chip(
                        label: Text(
                          status.toUpperCase(),
                          style: const TextStyle(fontSize: 10),
                        ),
                        backgroundColor: status == "open"
                            ? Colors.green.shade50
                            : Colors.grey.shade200,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Posted ${_timeAgo(widget.createdAt)} · ${_expiresIn()}",
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),

            if (!isLoading && hospitalLat != null && hospitalLng != null)
              SizedBox(
                height: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(hospitalLat!, hospitalLng!),
                      initialZoom: 12,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.mobile',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(hospitalLat!, hospitalLng!),
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.local_hospital,
                              color: Colors.red,
                              size: 32,
                            ),
                          ),
                          ...matches.map(
                            (donor) => Marker(
                              point: LatLng(
                                donor["latitude"],
                                donor["longitude"],
                              ),
                              width: 36,
                              height: 36,
                              child: Icon(
                                Icons.bloodtype,
                                color: Colors.blue.shade700,
                                size: 28,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            if (!isLoading && matches.isEmpty)
              _EmptyState(
                icon: Icons.search_off,
                text:
                    "No eligible donors found nearby yet. Pull down to refresh.",
              )
            else if (!isLoading)
              ...matches.map((donor) {
                final donorId = donor["id"];
                final respStatus = responsesState[donorId];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: scheme.primary.withValues(
                              alpha: 0.1,
                            ),
                            child: Text(
                              donor["blood_type"] ?? "?",
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: scheme.primary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  donor["full_name"] ?? "Anonymous Donor",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "${donor['distance_km']} km away · ${donor['phone_number']}",
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (respStatus != null)
                            Chip(
                              avatar: Icon(
                                respStatus == "accepted"
                                    ? Icons.check_circle
                                    : Icons.cancel,
                                color: respStatus == "accepted"
                                    ? Colors.green
                                    : Colors.red,
                                size: 16,
                              ),
                              label: Text(
                                respStatus.toUpperCase(),
                                style: const TextStyle(fontSize: 10),
                              ),
                              backgroundColor: Colors.grey.shade100,
                              side: BorderSide.none,
                            )
                          else
                            Text(
                              "Awaiting response",
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
