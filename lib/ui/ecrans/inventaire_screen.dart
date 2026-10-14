// lib/ui/ecrans/inventaire_screen.dart
// Nouvelle interface — INVENTAIRE SÉLECTIONNÉ (maquette « Hub », 4.13). Comme l'ancienne version, on
// choisit un inventaire avant toute saisie (liste de l'accueil, onglet Scanner) ; cet écran rappelle
// l'inventaire en cours puis ouvre les saisies :
//  - carte « Inventaire en cours » : nom, référence, pourcentage, barre avec « 110 / 130 » sur la même
//    ligne, saisies sur ce téléphone, « Actualiser » (calcul À LA DEMANDE, lib/ui/avancement.dart :
//    progression « Rayon i/n », Annuler, motif d'échec, « Se reconnecter ») ;
//  - Saisie guidée (choix du rayon), Scan continu, « Reprendre » au dernier rayon si une saisie existe ;
//  - Écarts (grisé « Pas encore d'écart » s'il n'y en a aucun) et Restant à faire (grisé « Super ! tout
//    a été saisi » à 100 %).
// Les saisies faites ensuite sur le téléphone sont ajoutées à l'affichage sans nouvelle requête.
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/ui/avancement.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/navigation.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/widgets/chargement_erreur.dart';
import 'package:prestinv/widgets/reconnexion.dart';
import 'package:provider/provider.dart';

class NvInventaireScreen extends StatefulWidget {
  final Inventory inventaire;
  const NvInventaireScreen({super.key, required this.inventaire});

  @override
  State<NvInventaireScreen> createState() => _NvInventaireScreenState();
}

class _NvInventaireScreenState extends State<NvInventaireScreen> {
  final _avancement = AvancementCalcul();

  Inventory get _inv => widget.inventaire;

  @override
  void initState() {
    super.initState();
    InventaireCourant.ecrire(_inv.id);
    _avancement.charger(_inv.id);
  }

  @override
  void dispose() {
    _avancement.annuler();
    _avancement.dispose();
    super.dispose();
  }

  ApiService _api() {
    final auth = context.read<AuthProvider>();
    return ApiService(baseUrl: context.read<AppConfig>().currentApiUrl, cookie: () => auth.sessionCookie);
  }

  Future<void> _actualiser() async {
    if (_avancement.enCours) return; // anti double appui
    await _avancement.actualiser(_api(), _inv.id);
  }

  void _annuler() {
    if (!_avancement.enCours) return;
    _avancement.annuler();
    nvMessage(context, 'Actualisation de l\'avancement annulée.', ton: context.nv.neutre);
  }

  Future<void> _aller(Future<void> Function() ouvrir) async {
    await ouvrir();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    SaisieQueue? q;
    try {
      q = context.watch<SaisieQueue>();
    } catch (_) {}
    final officine = (auth.user?.officine ?? '').trim();
    return ListenableBuilder(
      listenable: _avancement,
      builder: (context, _) {
        final lignes = q?.lignes(inventaireId: _inv.id) ?? const <SaisieLigne>[];
        final calcule = _avancement.resultat(_inv.id);
        final etat = etatAvancement(calcule, lignesLocales: lignes.map((s) => s.ligneId));
        final nv = context.nv;
        // Écarts : grisé seulement si le dernier calcul n'en a trouvé aucun et que rien n'a été saisi depuis.
        final saisiesDepuis = calcule == null ? lignes.isNotEmpty : lignes.any((s) => s.modifieLe.isAfter(calcule.calculeA));
        final sansEcart = etat.ecarts == 0 && !saisiesDepuis;
        final toutSaisi = etat.action == ActionInventaire.reverifier;
        return NvScaffold(
          surtitre: 'Prestige Inventaire',
          title: officine.isEmpty ? 'Inventaire' : officine,
          wide: true,
          header: [
            _CarteEnCours(
              inventaire: _inv,
              lignes: lignes,
              avancement: _avancement,
              etat: etat,
              onActualiser: _actualiser,
              onAnnuler: _annuler,
            ),
          ],
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
            _BoutonReprendre(
              lignes: lignes,
              onTap: (rayonId, scan) => _aller(() => scan ? NvAller.scan(context, _inv) : NvAller.guidee(context, _inv, rayonId: rayonId)),
            ),
            _CarteMode(
              key: const ValueKey('nv-saisie-guidee'),
              icon: Icons.edit_note,
              titre: 'Saisie guidée',
              detail: 'Produit par produit, rayon par rayon',
              onTap: () => _aller(() => NvAller.guidee(context, _inv)),
            ),
            const SizedBox(height: 12),
            _CarteMode(
              key: const ValueKey('nv-scan-continu'),
              icon: Icons.qr_code_scanner,
              titre: 'Scan continu',
              detail: 'Scanner les boîtes à la suite',
              onTap: () => _aller(() => NvAller.scan(context, _inv)),
            ),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: _Tuile(
                    key: const ValueKey('nv-tuile-ecarts'),
                    titre: 'Écarts',
                    detail: sansEcart
                        ? 'Pas encore d\'écart'
                        : (etat.ecarts != null && !saisiesDepuis ? '${etat.ecarts} produit(s) en écart' : 'Voir les écarts'),
                    couleurDetail: etat.ecarts != null && etat.ecarts! > 0 && !saisiesDepuis ? nv.manquant : null,
                    grise: sansEcart,
                    onTap: () => _aller(() => NvAller.ecarts(context, _inv)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Tuile(
                    key: const ValueKey('nv-tuile-restants'),
                    titre: 'Restant à faire',
                    detail: toutSaisi ? 'Super ! tout a été saisi' : (etat.restants != null ? '${etat.restants} produit(s)' : 'Voir les restants'),
                    couleurDetail: toutSaisi ? nv.ok.fg : (etat.restants != null ? nv.attente.fg : null),
                    grise: toutSaisi,
                    onTap: () => _aller(() => NvAller.restants(context, _inv)),
                  ),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

/// Carte « Inventaire en cours » (maquette Hub) dans l'en-tête bleu.
class _CarteEnCours extends StatelessWidget {
  final Inventory inventaire;
  final List<SaisieLigne> lignes;
  final AvancementCalcul avancement;
  final EtatAvancement etat;
  final VoidCallback onActualiser;
  final VoidCallback onAnnuler;
  const _CarteEnCours({
    required this.inventaire,
    required this.lignes,
    required this.avancement,
    required this.etat,
    required this.onActualiser,
    required this.onAnnuler,
  });

  @override
  Widget build(BuildContext context) {
    final calcule = avancement.resultat(inventaire.id);
    final envoyees = lignes.where((s) => s.envoyee).length;
    final calculIci = avancement.enCours && avancement.inventaireId == inventaire.id;
    final erreur = avancement.erreurPour(inventaire.id);
    final details = '${lignes.length} saisie(s) sur ce téléphone · $envoyees envoyée(s)';
    final rayons = calcule == null
        ? null
        : [
            'Rayons : ${calcule.termines} terminé(s) sur ${calcule.total}',
            if (calcule.commences > 0) '${calcule.commences} commencé(s)',
            if (calcule.inconnus > 0) '${calcule.inconnus} non lu(s)',
          ].join(' · ');
    final heure = calcule == null ? null : 'Avancement à ${calcule.heure()}';
    final pct = etat.pourcentage == null ? null : pourcentageAffiche(etat);
    final fraction = etat.pourcentage == null ? null : (etat.pourcentage! / 100).clamp(0.0, 1.0);
    final compte = etat.comptes != null && etat.total != null ? '${etat.comptes} / ${etat.total}' : null;
    return Semantics(
      container: true,
      label: 'Inventaire en cours : ${inventaire.libelle}. $details${pct != null ? '. Avancement $pct' : ''}${rayons != null ? '. $rayons' : ''}${heure != null ? '. $heure' : ''}',
      child: Container(
        key: const ValueKey('nv-en-cours'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('INVENTAIRE EN COURS', style: TextStyle(color: Pal.headerMuted, fontSize: 12, letterSpacing: 1)),
                Text(inventaire.libelle,
                    key: const ValueKey('nv-en-cours-nom'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                if (inventaire.id.isNotEmpty)
                  Text(inventaire.id, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Pal.headerMuted, fontSize: 12.5)),
              ]),
            ),
            if (pct != null)
              Container(
                key: const ValueKey('nv-avancement-pct'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Pal.amber, borderRadius: BorderRadius.circular(999)),
                child: Text(pct, style: const TextStyle(color: Pal.onAmber, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
          ]),
          if (fraction != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: fraction, minHeight: 8, color: Pal.amber, backgroundColor: Colors.white.withValues(alpha: 0.2)),
                ),
              ),
              if (compte != null) ...[
                const SizedBox(width: 10),
                Text(compte, key: const ValueKey('nv-avancement-compte'), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ]),
          ],
          const SizedBox(height: 8),
          if (calculIci)
            ProgressionAvancement(avancement: avancement, onAnnuler: onAnnuler)
          else
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(details, style: const TextStyle(color: Color(0xFFDCE6F2), fontSize: 13)),
                  if (rayons != null) Text(rayons, style: const TextStyle(color: Pal.headerMuted, fontSize: 12.5)),
                  if (heure != null)
                    Text(heure, key: const ValueKey('nv-avancement-heure'), style: const TextStyle(color: Pal.headerMuted, fontSize: 12.5)),
                ]),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const ValueKey('nv-actualiser-avancement'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white54,
                  side: const BorderSide(color: Colors.white54),
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                onPressed: avancement.enCours ? null : onActualiser,
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('Actualiser'),
              ),
            ]),
          if (erreur != null && !calculIci) ErreurAvancement(erreur: erreur, onReessayer: onActualiser),
        ]),
      ),
    );
  }
}

/// Calcul en cours : « Rayon 3/12 », barre de progression, Annuler (à droite, loin du bouton d'origine :
/// un double appui sur « Actualiser » ne peut pas annuler).
class ProgressionAvancement extends StatelessWidget {
  final AvancementCalcul avancement;
  final VoidCallback onAnnuler;
  const ProgressionAvancement({super.key, required this.avancement, required this.onAnnuler});

  @override
  Widget build(BuildContext context) {
    final n = avancement.rayons;
    final texte = n == 0 ? 'Lecture des rayons…' : 'Rayon ${avancement.rayon}/$n';
    return Semantics(
      liveRegion: true,
      label: 'Calcul de l\'avancement : $texte',
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(texte, key: const ValueKey('nv-avancement-progression'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14.5)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: n == 0 ? null : (avancement.rayon - 1).clamp(0, n) / n,
                minHeight: 6,
                color: Pal.amber,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        TextButton(
          key: const ValueKey('nv-annuler-avancement'),
          style: TextButton.styleFrom(
              foregroundColor: Colors.white, minimumSize: const Size(48, 48), textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w600)),
          onPressed: onAnnuler,
          child: const Text('Annuler'),
        ),
      ]),
    );
  }
}

/// Échec du calcul : motif exact (réseau, session…), le dernier avancement connu reste affiché.
class ErreurAvancement extends StatelessWidget {
  final Object erreur;
  final VoidCallback onReessayer;
  const ErreurAvancement({super.key, required this.erreur, required this.onReessayer});

  @override
  Widget build(BuildContext context) {
    final session = estSessionExpiree(erreur);
    return Container(
      key: const ValueKey('nv-avancement-erreur'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
      decoration: BoxDecoration(color: const Color(0xFF7F1D1D).withValues(alpha: 0.55), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(session ? Icons.lock_clock : Icons.cloud_off, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Avancement non actualisé : ${AvancementCalcul.motif(erreur)}', style: const TextStyle(color: Colors.white, fontSize: 13.5))),
        ]),
        if (session)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('nv-avancement-reconnecter'),
              style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(48, 48)),
              onPressed: () async {
                if (await demanderReconnexion(context)) onReessayer();
              },
              child: const Text('Se reconnecter'),
            ),
          ),
      ]),
    );
  }
}

/// « Reprendre : rayon … » (dernière saisie guidée) ou « Reprendre le scan continu ».
class _BoutonReprendre extends StatelessWidget {
  final List<SaisieLigne> lignes;
  final void Function(String? rayonId, bool scan) onTap;
  const _BoutonReprendre({required this.lignes, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final derniere = lignes.reversed.where((s) => s.origine == OrigineSaisie.guidee || s.origine == OrigineSaisie.rapide).firstOrNull;
    if (derniere == null) return const SizedBox.shrink();
    final scan = derniere.origine == OrigineSaisie.rapide || derniere.rayonId == null;
    final texte = scan ? 'Reprendre le scan continu' : 'Reprendre : rayon ${derniere.rayonLibelle ?? derniere.rayonId}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const ValueKey('nv-reprendre'),
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(fontSize: 15, fontWeight: FontWeight.bold)),
          onPressed: () => onTap(scan ? null : derniere.rayonId, scan),
          icon: const Icon(Icons.play_arrow_rounded, size: 24),
          label: Text(texte, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

class _CarteMode extends StatelessWidget {
  final IconData icon;
  final String titre;
  final String detail;
  final VoidCallback onTap;
  const _CarteMode({super.key, required this.icon, required this.titre, required this.detail, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    return SoftCard(
      onTap: onTap,
      semantique: '$titre : $detail',
      bordure: nv.ligne,
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(width: 48, height: 48, decoration: BoxDecoration(color: nv.info.bg, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: nv.info.fg, size: 26)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titre, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: nv.action)),
            Text(detail, style: TextStyle(color: nv.gris, fontSize: 13.5)),
          ]),
        ),
        Icon(Icons.chevron_right, color: nv.action),
      ]),
    );
  }
}

/// Tuile Écarts / Restant à faire ; [grise] : pointillés, non touchable (rien à y faire).
class _Tuile extends StatelessWidget {
  final String titre;
  final String detail;
  final Color? couleurDetail;
  final bool grise;
  final VoidCallback onTap;
  const _Tuile({super.key, required this.titre, required this.detail, required this.onTap, this.couleurDetail, this.grise = false});

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    final contenu = Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(titre, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: grise ? nv.gris : nv.action)),
        const SizedBox(height: 4),
        Text(detail, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: couleurDetail ?? nv.gris)),
      ]),
    );
    if (grise) {
      return Semantics(
        label: '$titre : $detail',
        enabled: false,
        excludeSemantics: true,
        child: CustomPaint(
          painter: _Pointilles(nv.ligne),
          child: Container(decoration: BoxDecoration(color: nv.page, borderRadius: BorderRadius.circular(14)), child: contenu),
        ),
      );
    }
    return SoftCard(onTap: onTap, bordure: nv.ligne, semantique: '$titre : $detail', padding: EdgeInsets.zero, child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 48), child: contenu));
  }
}

class _Pointilles extends CustomPainter {
  final Color couleur;
  _Pointilles(this.couleur);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = couleur
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final chemin = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)));
    for (final m in chemin.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, d + 5), p);
      }
    }
  }

  @override
  bool shouldRepaint(_Pointilles old) => old.couleur != couleur;
}
