import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_screen.dart';

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

  @override
  void initState() {
    super.initState();
    token = widget.token;
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
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    super.dispose();
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
        });
        _showSnack("You're registered as a $bloodType donor.");
      } else {
        _showSnack("Registration error: ${res.body}");
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
                        RequestScreen(requesterId: userId!, token: token),
                  ),
                ),
                icon: const Icon(Icons.emergency),
                label: const Text("Post an Urgent Blood Request"),
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

class RequestScreen extends StatefulWidget {
  final String requesterId;
  final String token; // <--- Add token parameter

  const RequestScreen({
    super.key,
    required this.requesterId,
    required this.token, // <--- Require it in constructor
  });

  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> {
  final hospitalCtrl = TextEditingController();
  final unitsCtrl = TextEditingController(text: "1");
  String bloodType = "O-";

  List<dynamic> matches = [];
  Map<String, String> responsesState = {};
  String? currentRequestId;
  bool isSearching = false;
  bool hasSearched = false;

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

    setState(() {
      isSearching = true;
      hasSearched = true;
      matches.clear();
      responsesState.clear();
    });

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
          "urgency": "critical",
        }),
      );

      if (res.statusCode == 201) {
        final data = jsonDecode(res.body);
        currentRequestId = data["id"];

        final matchRes = await http.get(
          Uri.parse("$baseUrl/blood-requests/$currentRequestId/matches"),
        );
        if (matchRes.statusCode == 200) {
          setState(() => matches = jsonDecode(matchRes.body)["matches"] ?? []);
          _fetchResponses();
        }
      } else {
        _showSnack("Failed to create request: ${res.body}");
      }
    } catch (e) {
      _showSnack("Error finding donors: $e");
    } finally {
      setState(() => isSearching = false);
    }
  }

  Future<void> _respond(String donorId, String status) async {
    if (currentRequestId == null) return;
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/blood-requests/$currentRequestId/respond"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${widget.token}",
        },
        body: jsonEncode({"donor_id": donorId, "status": status}),
      );
      if (res.statusCode == 201) {
        setState(() => responsesState[donorId] = status);
      } else {
        _showSnack("Failed to submit response: ${res.body}");
      }
    } catch (e) {
      _showSnack("Error connecting to server: $e");
    }
  }

  Future<void> _fetchResponses() async {
    if (currentRequestId == null) return;
    try {
      final res = await http.get(
        Uri.parse("$baseUrl/blood-requests/$currentRequestId/responses"),
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LabeledField(label: "Hospital name"),
                  TextField(controller: hospitalCtrl),
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
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: isSearching ? null : _submitRequest,
                      icon: isSearching
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
                        isSearching ? "Searching..." : "Find Donors Near Me",
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (currentRequestId != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.amber.shade800,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "Demo mode: tap accept/decline to simulate a donor responding.",
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          Expanded(
            child: !hasSearched
                ? _EmptyState(
                    icon: Icons.bloodtype_outlined,
                    text:
                        "Enter request details above and search for nearby donors.",
                  )
                : matches.isEmpty && !isSearching
                ? _EmptyState(
                    icon: Icons.search_off,
                    text: "No eligible donors found nearby.",
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: matches.length,
                    itemBuilder: (_, i) {
                      final donor = matches[i];
                      final donorId = donor["id"];
                      final status = responsesState[donorId];
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                if (status != null)
                                  Chip(
                                    avatar: Icon(
                                      status == "accepted"
                                          ? Icons.check_circle
                                          : Icons.cancel,
                                      color: status == "accepted"
                                          ? Colors.green
                                          : Colors.red,
                                      size: 16,
                                    ),
                                    label: Text(
                                      status.toUpperCase(),
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                    backgroundColor: Colors.grey.shade100,
                                    side: BorderSide.none,
                                  )
                                else
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                        ),
                                        onPressed: () =>
                                            _respond(donorId, "accepted"),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.cancel,
                                          color: Colors.red,
                                        ),
                                        onPressed: () =>
                                            _respond(donorId, "declined"),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
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
