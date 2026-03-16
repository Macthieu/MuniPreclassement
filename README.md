# MuniPreclassement

MuniPreclassement est l'outil specialise de preclassement documentaire de la suite Orchiviste/Muni.

## Mission

Produire des suggestions de classement deterministes et exploitables via contrat CLI JSON V1, sans logique IA non deterministe dans cette phase.

## Positionnement

- Outil autonome executable localement.
- Integrable dans Orchiviste (cockpit/hub) via contrat commun OrchivisteKit.
- Peut reutiliser la sortie JSON de MuniMetadonnees comme seed de preclassement.

## Version

- Version de release: `0.2.0`
- Tag Git: `v0.2.0`

## Contrat CLI JSON V1

Commande canonique:

```bash
muni-preclassement-cli run --request /path/request.json --result /path/result.json
```

Entrees V1 supportees:

- `parameters.text` (texte inline)
- `parameters.source_path` (chemin ou `file://` vers un fichier texte)
- `parameters.metadata_report_path` (rapport JSON MuniMetadonnees)
- `input_artifacts[]` (`kind=input` pour texte, `kind=report` pour metadata)
- `parameters.output_report_path` (optionnel) pour exporter un rapport JSON de preclassement

Parametres optionnels:

- `max_suggestions` (1...5, defaut 3)

Sorties:

- `ToolResult` canonique dans `--result`
- statut nominal: `succeeded` ou `needs_review`
- statut d'erreur: `failed`

## Build et tests

```bash
swift package resolve
swift build
swift test
```

## Licence

GNU GPL v3.0, voir [LICENSE](LICENSE).
