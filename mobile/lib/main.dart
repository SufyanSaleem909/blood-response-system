import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

// Use 10.0.2.2 for Android emulator to reach your PC's localhost.
// Use your PC's actual LAN IP if testing on a real phone.
const String baseUrl = "http://192.168.100.53:8000";

void main() => runApp(const BloodApp());

class BloodApp extends StatelessWidget {
  const BloodApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blood Response',
      theme: ThemeData(primarySwatch: Colors.red, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? userId;
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  String bloodType = "O-";
  final bloodTypes = ["O-", "O+", "A-", "A+", "B-", "B+", "AB-", "AB+"];

  Future<Position> _getLocation() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return Geolocator.getCurrentPosition();
  }

  Future<void> _registerUser() async {
    final pos = await _getLocation();
    final res = await http.post(
      Uri.parse("$baseUrl/users/"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "phone_number": phoneCtrl.text,
        "full_name": nameCtrl.text,
        "blood_type": bloodType,
        "latitude": pos.latitude,
        "longitude": pos.longitude,
      }),
    );
    if (res.statusCode == 201) {
      final data = jsonDecode(res.body);
      setState(() => userId = data["id"]);
      _showSnack("Registered! You're now a donor: $bloodType");
    } else {
      _showSnack("Error: ${res.body}");
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Blood Response System")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "Full name"),
            ),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(labelText: "Phone (+92...)"),
            ),
            DropdownButton<String>(
              value: bloodType,
              items: bloodTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => bloodType = v!),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _registerUser,
              child: const Text("Register as donor"),
            ),
            const Divider(height: 40),
            if (userId != null)
              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RequestScreen(requesterId: userId!),
                  ),
                ),
                child: const Text("Post an urgent blood request"),
              ),
          ],
        ),
      ),
    );
  }
}

class RequestScreen extends StatefulWidget {
  final String requesterId;
  const RequestScreen({super.key, required this.requesterId});
  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> {
  final hospitalCtrl = TextEditingController();
  final unitsCtrl = TextEditingController(text: "1");
  String bloodType = "O-";
  final bloodTypes = ["O-", "O+", "A-", "A+", "B-", "B+", "AB-", "AB+"];
  List<dynamic> matches = [];

  Future<void> _submitRequest() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied)
      perm = await Geolocator.requestPermission();
    final pos = await Geolocator.getCurrentPosition();

    final res = await http.post(
      Uri.parse("$baseUrl/blood-requests/"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "requester_id": widget.requesterId,
        "blood_type_needed": bloodType,
        "units_needed": int.tryParse(unitsCtrl.text) ?? 1,
        "hospital_name": hospitalCtrl.text,
        "latitude": pos.latitude,
        "longitude": pos.longitude,
        "urgency": "critical",
      }),
    );
    if (res.statusCode == 201) {
      final data = jsonDecode(res.body);
      final matchRes = await http.get(
        Uri.parse("$baseUrl/blood-requests/${data['id']}/matches"),
      );
      setState(() => matches = jsonDecode(matchRes.body)["matches"]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Urgent Blood Request")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: hospitalCtrl,
              decoration: const InputDecoration(labelText: "Hospital name"),
            ),
            TextField(
              controller: unitsCtrl,
              decoration: const InputDecoration(labelText: "Units needed"),
              keyboardType: TextInputType.number,
            ),
            DropdownButton<String>(
              value: bloodType,
              items: bloodTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => bloodType = v!),
            ),
            ElevatedButton(
              onPressed: _submitRequest,
              child: const Text("Find donors"),
            ),
            const Divider(height: 30),
            Expanded(
              child: ListView.builder(
                itemCount: matches.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(matches[i]["full_name"]),
                  subtitle: Text(
                    "${matches[i]['blood_type']} · ${matches[i]['distance_km']} km away",
                  ),
                  trailing: Text(matches[i]["phone_number"]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
