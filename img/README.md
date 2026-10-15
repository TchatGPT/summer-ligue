# Photos des lots

La page Finale affiche une photo par lot. Les fichiers en place :

| Fichier               | Lot                                 |
|-----------------------|-------------------------------------|
| `lot-mw4.png`         | Call of Duty : Modern Warfare 4     |
| `lot-goxlr-mini.png`  | GoXLR Mini                          |

Pour en remplacer une, garde le même nom de fichier et ces contraintes :

- **PNG à fond transparent** — la carte pose un halo coloré derrière l'objet,
  un fond blanc ou noir casserait l'effet ;
- **~460 px sur le plus grand côté**, l'image est affichée à ~270 px de haut ;
- **moins de 300 Ko**, pour que la page reste rapide.

Si un fichier manque ou ne charge pas, la carte bascule toute seule sur un
visuel dessiné en CSS : jamais d'image cassée sur le site.
