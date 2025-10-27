import'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String supabaseUrl = 'https://vhuwvvdlkimqoztkqluw.supabase.co';
const String supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZodXd2dmRsa2ltcW96dGtxbHV3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ1NjM2OTEsImV4cCI6MjA3MDEzOTY5MX0.MWH2bqqQnYMfzDTsQOJyERyAHvpa_8YYnuGNEJsWTmk';
final supabase = Supabase.instance.client;

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseKey,
  );
}
