# React Preview

Ce projet permet de déployer automatiquement des environnements de prévisualisation (preview) pour chaque branche d'un dépôt Git contenant une application React (conçue avec Vite). 

Chaque branche est compilée et servie sous un sous-répertoire spécifique, permettant ainsi d'accéder à plusieurs versions de l'application simultanément.

## 🚀 Fonctionnement

1. **Synchronisation** : Un script (`sync.sh`) surveille le dépôt Git configuré toutes les 120 secondes.
2. **Build Automatique** : Pour chaque branche (pouvant être filtrée par regex), le script :
   - Installe les dépendances avec `npm ci`.
   - Compile l'application avec `npm run build` en injectant le bon `VITE_BASE_PATH`.
3. **Déploiement** : Les fichiers compilés sont placés dans `/var/www/html/${BASE_PATH}/${branch_name}`.
4. **Service Web** : Nginx sert les fichiers et gère le routage SPA (History API) pour chaque environnement.
5. **Nettoyage** : Les environnements correspondant à des branches supprimées sur le dépôt distant sont automatiquement effacés du serveur.

## 🛠️ Configuration

Le conteneur se configure via des variables d'environnement obligatoires :

| Variable | Description | Exemple |
| :--- | :--- | :--- |
| `REPO_URL` | URL du dépôt Git (HTTPS) | `https://github.com/user/my-react-app.git` |
| `DOMAIN` | Nom de domaine utilisé (pour les logs/liens) | `preview.mon-site.com` |
| `BASE_PATH` | Préfixe du chemin URL de base | `app` ou `/` |

Variables optionnelles :

| Variable | Description | Défaut |
| :--- | :--- | :--- |
| `BRANCH_REGEX` | Regex pour filtrer les branches à déployer | (Toutes les branches) |

## 📦 Utilisation avec Docker

L'image Docker est disponible sur Docker Hub sous le nom `ocelus/react-preview`.

### Lancer avec Docker Run

```bash
docker run -d \
  -e REPO_URL="https://github.com/votre-compte/votre-projet.git" \
  -e DOMAIN="localhost" \
  -e BASE_PATH="preview" \
  -p 8080:80 \
  --name react-preview \
  ocelus/react-preview
```

### Exemple de Docker Compose

```yaml
version: '3.8'

services:
  react-preview:
    image: ocelus/react-preview
    ports:
      - "8080:80"
    environment:
      - REPO_URL=https://github.com/mon-organisation/mon-projet-react.git
      - DOMAIN=preview.mondomaine.com
      - BASE_PATH=projets
      - BRANCH_REGEX=^(feat|fix|hotfix)/.* # Optionnel
    volumes:
      - preview_data:/var/www/html
    restart: always

volumes:
  preview_data:
```

## 📝 Structure du projet

- `Dockerfile` : Basé sur Node 20 Alpine, installe Git, Nginx et Gettext.
- `sync.sh` : Script principal de synchronisation, build et nettoyage.
- `nginx.conf.template` : Template Nginx configuré pour supporter le routage SPA sur des sous-chemins dynamiques.

## 🔗 Accès aux environnements

Une fois déployées, les branches sont accessibles via :
`https://${DOMAIN}/${BASE_PATH}/${nom-de-la-branche}/`

*Note : Les noms de branches sont normalisés (passage en minuscules, remplacement des caractères spéciaux par des tirets).*
