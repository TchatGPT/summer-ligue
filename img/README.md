# Photos des lots

La page Finale affiche une photo pour chaque lot. Dépose simplement les
fichiers ici, avec **exactement** ces noms :

| Fichier               | Lot                                 |
|-----------------------|-------------------------------------|
| `lot-mw4.png`         | Call of Duty : Modern Warfare 4     |
| `lot-goxlr-mini.png`  | GoXLR Mini                          |

Ce qui marche le mieux :

- **PNG à fond transparent** — la carte pose déjà un halo coloré derrière
  l'objet, un fond blanc ou noir casserait l'effet ;
- **environ 800 px de large**, l'image est affichée à ~250 px de haut et
  mise à l'échelle automatiquement ;
- **moins de 300 Ko** par fichier, pour que la page reste rapide.

Tant qu'un fichier est absent, la carte affiche un visuel dessiné en CSS à
la place : rien ne casse, et la photo apparaît dès que tu pousses le PNG.
