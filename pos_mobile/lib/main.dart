import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'data/datasources/auth_api_source.dart';
import 'data/datasources/local_db_source.dart';
import 'data/datasources/remote_api_source.dart';
import 'data/repositories/pos_repository_impl.dart';
import 'domain/usecases/process_checkout.dart';
import 'presentation/controllers/auth_provider.dart';
import 'presentation/controllers/pos_provider.dart';
import 'presentation/pages/auth_gate.dart';

void main() {
  final remoteApiSource = RemoteApiSource();
  final localDbSource = LocalDbSource();
  final posRepository = PosRepositoryImpl(
    localDbSource: localDbSource,
    remoteApiSource: remoteApiSource,
  );
  final processCheckoutUseCase = ProcessCheckoutUseCase(posRepository);
  final authProvider = AuthProvider(
    api: AuthApiSource(),
    onTokenChanged: (token) => remoteApiSource.accessToken = token,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(
          create: (_) => PosProvider(
            processCheckoutUseCase: processCheckoutUseCase,
            remoteApiSource: remoteApiSource,
          ),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'POS gntg',
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
          textTheme: GoogleFonts.bricolageGrotesqueTextTheme(),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFC45A34),
            primary: const Color(0xFFC45A34),
          ),
        ),
        home: const AuthGate(),
      ),
    ),
  );
}
