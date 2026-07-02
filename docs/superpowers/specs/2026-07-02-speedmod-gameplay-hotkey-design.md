# Raccourci clavier pour ajuster le speedmod pendant ScreenGameplay

## Contexte

Actuellement, le speedmod (XMod / MMod / CMod) ne peut être changé qu'avant le
début d'une chanson (ScreenPlayerOptions) ou, en mode Course/Marathon, entre
deux chansons via `ChangeSpeedModBeforeFirstNote.lua`. Il n'existe aucun moyen
de l'ajuster pendant que des notes défilent réellement sur `ScreenGameplay`.

Le thème contient déjà les briques nécessaires pour le faire :
- `GAMESTATE:ApplyGameCommand("mod,...", player)` applique un nouveau mod à
  chaud ; le NoteField se recalcule chaque frame donc l'effet est immédiat
  (utilisé par `BGAnimations/ScreenGameplay next course song/ChangeSpeedModBeforeFirstNote.lua`).
- `BGAnimations/ScreenGameplay underlay/default.lua` contient déjà un handler
  ctrl+R (redémarrer la chanson), avec le pattern exact de détection
  "ctrl maintenu + touche" (`DeviceButton_left ctrl` + `DeviceButton_r`),
  restreint à `PREFSMAN:GetPreference("EventMode")`.

## Objectif

Ajouter un raccourci clavier sur `ScreenGameplay` :
- **ctrl + Haut** : augmente le speedmod actif du joueur.
- **ctrl + Bas** : diminue le speedmod actif du joueur.

## Comportement détaillé

### Détection du mod actif et incrément

Pour chaque joueur humain (`GAMESTATE:GetHumanPlayers()`), on lit ses
`PlayerOptions('ModsLevel_Song')` et on détermine lequel de XMod / MMod / CMod
est actuellement actif (même logique que `ChangeSpeedModBeforeFirstNote.lua`
et `SL-PlayerOptions.lua`).

L'incrément appliqué dépend du type de mod actif :

| Mod  | Incrément | Borne haute | Borne basse |
|------|-----------|-------------|-------------|
| XMod | 0.05      | 10          | > 0         |
| MMod | 5         | 2000        | > 0         |
| CMod | 5         | 2000        | > 0         |

Ces bornes reprennent celles déjà utilisées dans `Scripts/SL-PlayerOptions.lua`.

### Application

1. Calcule la nouvelle valeur, clampée aux bornes ci-dessus.
2. Construit une chaîne GameCommand : `"mod,%.2fx"` (XMod), `"mod,m%d"` (MMod),
   ou `"mod,c%d"` (CMod).
3. Applique via `GAMESTATE:ApplyGameCommand(gcString, player)`.
4. Met à jour `SL[ToEnumShortString(player)].ActiveModifiers.SpeedMod`.
5. Diffuse `MESSAGEMAN:Broadcast("PlayerOptionsChanged", {Player=player})` pour
   que `BGAnimations/ScreenGameplay underlay/PerPlayer/NoteField/DisplayMods.lua`
   rafraîchisse immédiatement le texte du mod affiché à l'écran.

### Portée multi-joueurs

Aucune gestion spéciale : on boucle sur `GAMESTATE:GetHumanPlayers()` et on
applique le même ajustement à chaque joueur humain présent. Ce comportement
couvre naturellement le cas 1 joueur et 2 joueurs sans code additionnel.

### Disponibilité

Le raccourci n'est actif que si `PREFSMAN:GetPreference("EventMode")` est vrai
— même garde-fou que le raccourci ctrl+R existant dans
`BGAnimations/ScreenGameplay underlay/default.lua`.

### Cas limites

- Si un joueur n'a pas d'objet `PlayerOptions` valide (edge case), il est
  ignoré silencieusement pour cet ajustement — pas de crash.
- Le callback d'input est ajouté/retiré via `AddInputCallback` /
  `RemoveInputCallback` sur les commandes `OnCommand` / `OffCommand` de
  l'acteur, comme le pattern déjà utilisé ailleurs dans le thème
  (`ChangeSpeedModBeforeFirstNote.lua`).

## Architecture

Nouveau fichier : `BGAnimations/ScreenGameplay underlay/SpeedModHotkey.lua`.

C'est un acteur indépendant (`Def.Actor`), chargé depuis
`BGAnimations/ScreenGameplay underlay/default.lua` via un `LoadActor`
supplémentaire dans la liste d'acteurs déjà présente (aux côtés de
`TournamentMode.lua`, `NoteField/default.lua`, etc.). Il n'est pas fusionné
avec le `RestartHandler` déjà présent dans `default.lua`, afin de garder une
responsabilité unique par fichier, cohérent avec le reste du thème.

## Tests

Pas de framework de test automatisé dans ce thème Lua/ITGmania. Validation
manuelle en jeu :
- Lancer une chanson avec `EventMode` activé, vérifier que ctrl+Haut/Bas
  change la vitesse de défilement en temps réel et que le texte du mod
  affiché à l'écran se met à jour.
- Vérifier le clamp aux bornes hautes/basses pour chaque type de mod.
- Vérifier qu'avec `EventMode` désactivé, le raccourci ne fait rien.
