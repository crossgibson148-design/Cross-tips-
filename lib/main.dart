import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const CrossTipsApp());

class CrossTipsApp extends StatelessWidget {
  const CrossTipsApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Cross Tips', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF20C878), brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF0B1110), cardColor: const Color(0xFF151F1C),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: const Color(0xFF17221F),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
    home: const HomePage());
}

class MatchPick {
  MatchPick({required this.id, required this.home, required this.away, this.league = 'Other',
    required this.date, this.homeFor = 1.4, this.homeAgainst = 1.2, this.awayFor = 1.2,
    this.awayAgainst = 1.4, this.homeScore, this.awayScore});
  final String id, home, away, league, date;
  final double homeFor, homeAgainst, awayFor, awayAgainst;
  final int? homeScore, awayScore;
  Map<String, dynamic> toJson() => {'id':id,'home':home,'away':away,'league':league,'date':date,
    'homeFor':homeFor,'homeAgainst':homeAgainst,'awayFor':awayFor,'awayAgainst':awayAgainst,
    'homeScore':homeScore,'awayScore':awayScore};
  factory MatchPick.fromJson(Map<String,dynamic> j) => MatchPick(id:j['id'],home:j['home'],away:j['away'],
    league:j['league'] ?? 'Other',date:j['date'],homeFor:(j['homeFor'] as num).toDouble(),
    homeAgainst:(j['homeAgainst'] as num).toDouble(),awayFor:(j['awayFor'] as num).toDouble(),
    awayAgainst:(j['awayAgainst'] as num).toDouble(),homeScore:j['homeScore'],awayScore:j['awayScore']);
}

class Prediction {
  Prediction(this.home, this.draw, this.away, this.over15, this.over25, this.over35, this.btts, this.xgHome, this.xgAway);
  final double home, draw, away, over15, over25, over35, btts, xgHome, xgAway;
  String get result => home >= draw && home >= away ? '1 (Home)' : away >= home && away >= draw ? '2 (Away)' : 'X (Draw)';
}

double _pois(int k, double lambda) => math.exp(-lambda) * math.pow(lambda, k) / _fact(k);
double _fact(int n) { var v=1.0; for(var i=2;i<=n;i++) {v*=i;} return v; }
Prediction predict(MatchPick m) {
  final h = ((m.homeFor + m.awayAgainst) / 2).clamp(0.15, 4.5).toDouble();
  final a = ((m.awayFor + m.homeAgainst) / 2).clamp(0.15, 4.5).toDouble();
  var hw=0.0, dr=0.0, aw=0.0, under15=0.0, under25=0.0, under35=0.0, noBtts=0.0, total=0.0;
  // Normalize the finite score grid so displayed probabilities sum to 100%.
  // A 0–10 goal range keeps the omitted Poisson tail very small for our capped xG.
  for(var i=0;i<=10;i++) { for(var j=0;j<=10;j++) {
    final probability=_pois(i,h)*_pois(j,a);
    total+=probability;
    if(i>j) hw+=probability; else if(i==j) dr+=probability; else aw+=probability;
    if(i+j<=1) under15+=probability; if(i+j<=2) under25+=probability; if(i+j<=3) under35+=probability;
    if(i==0 || j==0) noBtts+=probability;
  }}
  if(total<=0) total=1;
  return Prediction(hw/total*100,dr/total*100,aw/total*100,
    (1-under15/total)*100,(1-under25/total)*100,(1-under35/total)*100,
    (1-noBtts/total)*100,h,a);
}

class HomePage extends StatefulWidget { const HomePage({super.key}); @override State<HomePage> createState()=>_HomePageState(); }
class _HomePageState extends State<HomePage> {
  List<MatchPick> matches=[]; bool loading=false; int tab=0; String apiToken='';
  @override void initState(){super.initState(); _load();}
  Future<void> _load() async { final p=await SharedPreferences.getInstance();
    final raw=p.getString('matches'); if(raw!=null){try{matches=(jsonDecode(raw) as List).map((e)=>MatchPick.fromJson(e)).toList();}catch(_){}}
    apiToken=p.getString('apiToken')??''; if(mounted)setState((){}); }
  Future<void> _save() async {final p=await SharedPreferences.getInstance(); await p.setString('matches',jsonEncode(matches.map((e)=>e.toJson()).toList()));}
  void _add(MatchPick m){setState(()=>matches.insert(0,m));_save();}
  Future<void> _remove(MatchPick m) async {setState(()=>matches.removeWhere((x)=>x.id==m.id));await _save();}
  Future<void> _fetchFixtures() async {
    if(apiToken.trim().isEmpty){_settings();return;}
    setState(()=>loading=true);
    try {
      final now=DateTime.now(); final day='${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
      final uri=Uri.https('api.football-data.org','/v4/matches',{'dateFrom':day,'dateTo':day});
      final res=await http.get(uri,headers:{'X-Auth-Token':apiToken.trim()}).timeout(const Duration(seconds:20));
      if(res.statusCode!=200) throw Exception('Provider returned ${res.statusCode}. Check your API token or plan.');
      final body=jsonDecode(res.body) as Map<String,dynamic>; final list=(body['matches'] as List? ?? []);
      var added=0;
      for(final item in list){final h=item['homeTeam']?['name']??'Home';final a=item['awayTeam']?['name']??'Away';
        if(matches.any((m)=>m.home==h&&m.away==a&&m.date==day))continue;
        matches.insert(0,MatchPick(id:'${DateTime.now().microsecondsSinceEpoch}_$added',home:h,away:a,
          league:item['competition']?['name']??'Football',date:day)); added++;}
      await _save(); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Imported $added fixtures. Add team statistics to improve predictions.')));
    } catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not load fixtures: $e')));}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> _settings() async {final c=TextEditingController(text:apiToken);
    await showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('Automatic fixtures'),content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Enter your football-data.org API token. The free/paid access and competitions depend on that provider.'),const SizedBox(height:12),TextField(controller:c,decoration:const InputDecoration(labelText:'API token'))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()async{apiToken=c.text.trim();final p=await SharedPreferences.getInstance();await p.setString('apiToken',apiToken);if(ctx.mounted)Navigator.pop(ctx);},child:const Text('Save'))]));}
  Future<void> _addDialog() async {final home=TextEditingController(),away=TextEditingController(),league=TextEditingController(text:'Premier League');
    final hf=TextEditingController(text:'1.5'),ha=TextEditingController(text:'1.1'),af=TextEditingController(text:'1.3'),aa=TextEditingController(text:'1.4');
    final form=GlobalKey<FormState>();
    await showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('Add a match'),content:SizedBox(width:420,child:SingleChildScrollView(child:Form(key:form,child:Column(children:[_field(home,'Home team'),_field(away,'Away team'),_field(league,'League'),const SizedBox(height:12),const Align(alignment:Alignment.centerLeft,child:Text('Team goals per match (recent average)',style:TextStyle(fontWeight:FontWeight.bold))),const SizedBox(height:8),Row(children:[Expanded(child:_field(hf,'Home scored')),const SizedBox(width:8),Expanded(child:_field(ha,'Home conceded'))]),Row(children:[Expanded(child:_field(af,'Away scored')),const SizedBox(width:8),Expanded(child:_field(aa,'Away conceded'))]),const SizedBox(height:8),const Text('Use recent goals scored/conceded per match. Defaults are examples; replace them with real statistics.',style:TextStyle(color:Colors.white60,fontSize:12))])))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:(){if(!form.currentState!.validate())return;final vals=[hf,ha,af,aa].map((c)=>double.tryParse(c.text)).toList();if(vals.any((v)=>v==null||v!<0||v>10)){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter statistics between 0 and 10.')));return;}
      _add(MatchPick(id:DateTime.now().microsecondsSinceEpoch.toString(),home:home.text.trim(),away:away.text.trim(),league:league.text.trim().isEmpty?'Other':league.text.trim(),date:DateTime.now().toIso8601String().substring(0,10),homeFor:vals[0]!,homeAgainst:vals[1]!,awayFor:vals[2]!,awayAgainst:vals[3]!));Navigator.pop(ctx);},child:const Text('Save match'))]}));}
  Widget _field(TextEditingController c,String label)=>Padding(padding:const EdgeInsets.only(bottom:9),child:TextFormField(controller:c,decoration:InputDecoration(labelText:label),validator:(v)=>v==null||v.trim().isEmpty?'Required':null));
  @override Widget build(BuildContext context){final today=DateTime.now().toIso8601String().substring(0,10);final todays=matches.where((m)=>m.date==today).toList();
    return Scaffold(appBar:AppBar(title:const Row(children:[Icon(Icons.sports_soccer,color:Color(0xFF20C878)),SizedBox(width:9),Text('CROSS TIPS',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:1.2))]),actions:[IconButton(onPressed:_settings,icon:const Icon(Icons.settings))]),
      body:tab==0? _dashboard(todays):tab==1?_allMatches():_history(),
      floatingActionButton:tab==2?null:FloatingActionButton.extended(onPressed:_addDialog,icon:const Icon(Icons.add),label:const Text('Add match')),
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:const [NavigationDestination(icon:Icon(Icons.dashboard_outlined),selectedIcon:Icon(Icons.dashboard),label:'Today'),NavigationDestination(icon:Icon(Icons.sports_soccer),label:'Matches'),NavigationDestination(icon:Icon(Icons.history),label:'History')]));}
  Widget _dashboard(List<MatchPick> todays)=>ListView(padding:const EdgeInsets.all(16),children:[Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(borderRadius:BorderRadius.circular(18),gradient:const LinearGradient(colors:[Color(0xFF164D37),Color(0xFF14231E)])),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('YOUR DAILY FOOTBALL EDGE',style:TextStyle(letterSpacing:1.3,color:Color(0xFF8CE6B6))),const SizedBox(height:8),const Text('Analyse. Predict. Track.',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),const SizedBox(height:6),Text('${todays.length} matches added today',style:const TextStyle(color:Colors.white70)),const SizedBox(height:14),Wrap(spacing:8,runSpacing:8,children:[FilledButton.icon(onPressed:_addDialog,icon:const Icon(Icons.edit_note),label:const Text('Enter match')),OutlinedButton.icon(onPressed:loading?null:_fetchFixtures,icon:loading?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.cloud_download_outlined),label:const Text('Fetch fixtures'))])])),const SizedBox(height:20),_sectionTitle('Today’s predictions'),if(todays.isEmpty) _empty('No matches yet','Add a match manually or fetch today’s fixtures.') else ...todays.map(_matchCard),const SizedBox(height:12),const Text('Predictions are statistical estimates, not guarantees. Verify team news, line-ups and odds before making decisions.',style:TextStyle(color:Colors.white54,fontSize:12))]);
  Widget _allMatches()=>ListView(padding:const EdgeInsets.all(16),children:[_sectionTitle('All matches (${matches.length})'),if(matches.isEmpty)_empty('Your match list is empty','Add your first football match.') else ...matches.map(_matchCard)]);
  Widget _history(){final done=matches.where((m)=>m.homeScore!=null&&m.awayScore!=null).toList();final correct=done.where((m){final p=predict(m);final actual=m.homeScore!>m.awayScore!?'1 (Home)':m.homeScore!<m.awayScore!?'2 (Away)':'X (Draw)';return p.result==actual;}).length;return ListView(padding:const EdgeInsets.all(16),children:[_sectionTitle('Prediction history'),Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:const Color(0xFF151F1C),borderRadius:BorderRadius.circular(16)),child:Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:[_stat('Settled','${done.length}'),_stat('1X2 correct','$correct'),_stat('Accuracy',done.isEmpty?'—':'${(correct/done.length*100).round()}%')]),),const SizedBox(height:14),if(done.isEmpty)_empty('No results recorded','Open a match and enter its final score to start tracking accuracy.') else ...done.map(_matchCard)]);}
  Widget _stat(String a,String b)=>Column(children:[Text(b,style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold,color:Color(0xFF65D99A))),Text(a,style:const TextStyle(color:Colors.white60,fontSize:12))]);
  Widget _sectionTitle(String t)=>Padding(padding:const EdgeInsets.only(bottom:12),child:Text(t,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)));
  Widget _empty(String title,String sub)=>Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(color:const Color(0xFF151F1C),borderRadius:BorderRadius.circular(16)),child:Column(children:[const Icon(Icons.sports_soccer,size:35,color:Color(0xFF65D99A)),const SizedBox(height:10),Text(title,style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:4),Text(sub,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white60))]));
  Widget _matchCard(MatchPick m){final p=predict(m);return Card(margin:const EdgeInsets.only(bottom:12),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Expanded(child:Text(m.league,style:const TextStyle(color:Color(0xFF65D99A),fontSize:12))),Text(m.date,style:const TextStyle(color:Colors.white54,fontSize:11)),PopupMenuButton<String>(onSelected:(v){if(v=='delete')_remove(m);if(v=='result')_resultDialog(m);},itemBuilder:(_)=>const [PopupMenuItem(value:'result',child:Text('Enter final score')),PopupMenuItem(value:'delete',child:Text('Delete match'))])]),Text('${m.home}  vs  ${m.away}',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:17)),if(m.homeScore!=null)Text('Final score: ${m.homeScore} - ${m.awayScore}',style:const TextStyle(color:Colors.white60)),const Divider(height:20),Row(children:[Expanded(child:_predictionTile('1',p.home)),Expanded(child:_predictionTile('X',p.draw)),Expanded(child:_predictionTile('2',p.away))]),const SizedBox(height:12),Wrap(spacing:7,runSpacing:7,children:[_pill('Over 1.5',p.over15),_pill('Under 1.5',100-p.over15),_pill('Over 2.5',p.over25),_pill('Under 2.5',100-p.over25),_pill('Over 3.5',p.over35),_pill('Under 3.5',100-p.over35),_pill('BTTS Yes',p.btts),_pill('BTTS No',100-p.btts)]),const SizedBox(height:10),Text('Model pick: ${p.result}  •  Expected goals: ${p.xgHome.toStringAsFixed(1)} - ${p.xgAway.toStringAsFixed(1)}',style:const TextStyle(color:Color(0xFF9EDDB9),fontSize:12))])));}
  Widget _predictionTile(String label,double value)=>Column(children:[Text(label,style:const TextStyle(color:Colors.white60)),Text('${value.round()}%',style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold))]);
  Widget _pill(String label,double v)=>Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:6),decoration:BoxDecoration(color:const Color(0xFF22332C),borderRadius:BorderRadius.circular(20)),child:Text('$label ${v.round()}%',style:const TextStyle(fontSize:11)));
  Future<void> _resultDialog(MatchPick m)async{final h=TextEditingController(text:m.homeScore?.toString()??''),a=TextEditingController(text:m.awayScore?.toString()??'');await showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('Record final score'),content:Row(children:[Expanded(child:TextField(controller:h,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:m.home))),const SizedBox(width:10),Expanded(child:TextField(controller:a,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:m.away)))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()async{final hs=int.tryParse(h.text), awayScore=int.tryParse(a.text);if(hs==null||awayScore==null||hs<0||awayScore<0)return;final i=matches.indexWhere((x)=>x.id==m.id);if(i>=0){final old=matches[i];matches[i]=MatchPick(id:old.id,home:old.home,away:old.away,league:old.league,date:old.date,homeFor:old.homeFor,homeAgainst:old.homeAgainst,awayFor:old.awayFor,awayAgainst:old.awayAgainst,homeScore:hs,awayScore:awayScore);setState((){});await _save();}if(ctx.mounted)Navigator.pop(ctx);},child:const Text('Save result'))]));}
}
