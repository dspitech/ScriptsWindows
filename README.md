## System Maintenance & Update Framework v2.0

> Script de maintenance avancée pour Windows 10/11 (optimisation, nettoyage et mises à jour Cloud).

![Status](https://img.shields.io/badge/status-stable-success)
![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-%3E%3D5.1-5391FE)

---

## Table des matières

- [System Maintenance & Update Framework v2.0](#system-maintenance--update-framework-v20)
- [Table des matières](#table-des-matières)
- [Fonctionnalités](#fonctionnalités)
- [Prérequis](#prérequis)
- [Avertissements](#avertissements)
- [Installation](#installation)
- [Utilisation](#utilisation)
- [Aperçu technique](#aperçu-technique)
- [Bonnes pratiques dutilisation](#bonnes-pratiques-dutilisation)
- [Personnalisation](#personnalisation)
- [FAQ](#faq)
- [Dépannage](#dépannage)
- [Roadmap](#roadmap)
- [Licence](#licence)
- [Support & Contributions](#support--contributions)

Framework de maintenance automatisée pour Windows 10/11, destiné à simplifier les tâches de nettoyage système et de gestion des mises à jour Windows.  
Ce script PowerShell exécute une série d’actions de maintenance avancée, adaptées à un usage professionnel (poste administrateur, environnement entreprise ou power user).

---

## Fonctionnalités

- **Réinitialisation de la connectivité Windows Update**
  - Suppression des restrictions GPO/WSUS liées à Windows Update (`HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate`).
  - Réinitialisation du proxy WinHTTP (`netsh winhttp reset proxy`).
  - Redémarrage du service Windows Update (`wuauserv`).

- **Gestion des mises à jour Windows (Cloud)**
  - Utilisation de l’API COM `Microsoft.Update.Session`.
  - Forçage de la source de mises à jour sur Internet (Cloud) plutôt que WSUS.
  - Détection des mises à jour critiques non installées.
  - Demande de confirmation interactive avant installation.
  - Affichage d’une barre de progression pendant l’installation.

- **Nettoyage approfondi du magasin de composants (WinSxS)**
  - Analyse de l’espace disque utilisé par le magasin de composants.
  - Exécution de `DISM.exe /Online /Cleanup-Image /AnalyzeComponentStore`.
  - Nettoyage avancé avec `DISM.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase` pour réduire la taille du dossier WinSxS.

- **Purge des fichiers temporaires et de la Corbeille**
  - Suppression des fichiers dans :
    - `%TEMP%`
    - `%WinDir%\Temp`
    - `%WinDir%\Prefetch`
  - Vidage silencieux de la Corbeille (`Clear-RecycleBin`).

- **Interface console claire**
  - Affichage d’un en-tête et de sections de type “STEP 1 / STEP 2 / ...”.
  - Messages colorés pour distinguer les étapes, succès et erreurs.
  - Pause finale avec `Read-Host` pour permettre de lire les résultats.

---

## Prérequis

- **Système d’exploitation**
  - Windows 10 ou Windows 11 (édition Pro/Entreprise recommandée).

- **Permissions**
  - Exécution **en tant qu’administrateur** (PowerShell élevé).
  - Compte avec droits suffisants pour :
    - Modifier la base de registre sous `HKLM`.
    - Gérer le service `wuauserv`.
    - Lancer `DISM.exe`.
    - Supprimer des fichiers système temporaires.

- **PowerShell**
  - PowerShell 5.1 ou supérieur (fonctionne également sous PowerShell 7+ si lancé en contexte administrateur).
  - Politique d’exécution permettant l’exécution de scripts locaux :
    - Par exemple : `RemoteSigned` ou `Bypass` (voir section Utilisation).

---

## Avertissements

- **Environnement entreprise**
  - La suppression des clés GPO/WSUS liées à Windows Update peut se heurter aux politiques de votre organisation.
  - À utiliser uniquement si vous comprenez l’impact sur la stratégie de mises à jour (bypass WSUS pour passer en mode Cloud).

- **Nettoyage WinSxS**
  - Le paramètre `/ResetBase` rend impossible la désinstallation de certaines mises à jour.
  - Recommandé sur des systèmes stables dont la configuration logicielle est figée.

- **Suppression de fichiers temporaires**
  - Des fichiers temporaires encore utilisés par certaines applications pourraient être supprimés (même si l’impact est généralement faible).
  - Assurez-vous d’avoir sauvegardé votre travail avant de lancer le script.

---

## Installation

1. **Cloner le dépôt**

   ```bash
   git clone https://github.com/<votre-compte>/<votre-repo>.git
   cd <votre-repo>
   ```

2. **Vérifier la présence du script**

   Le fichier `deploy.ps1` doit se trouver à la racine du projet.

---

## Utilisation

### 1. Ouvrir PowerShell en administrateur

- Rechercher **PowerShell** dans le menu Démarrer.
- Clic droit → **Exécuter en tant qu’administrateur**.

### 2. (Optionnel) Adapter la politique d’exécution

Si les scripts sont bloqués, exécuter :

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
```

Cela active l’exécution des scripts **uniquement pour la session courante**.

### 3. Naviguer dans le dossier du script

```powershell
cd "C:\chemin\vers\votre\repo"
```

### 4. Lancer le script

```powershell
.\deploy.ps1
```

Le script va alors :

1. Réinitialiser la configuration WSUS/proxy et le service Windows Update.
2. Analyser les mises à jour disponibles via Internet.
3. Vous demander **confirmation** avant d’installer les mises à jour détectées.
4. Lancer un nettoyage avancé du magasin de composants (WinSxS).
5. Purger les fichiers temporaires et vider la Corbeille.
6. Afficher un résumé de fin de maintenance.

---

## Aperçu technique

- **Technologie** : script `PowerShell` autonome (`deploy.ps1`), sans dépendance externe.
- **Mode d’exécution** : exécution locale, en session élevée (administrateur).
- **APIs utilisées** :
  - COM `Microsoft.Update.Session` pour la recherche et l’installation des mises à jour.
  - Outils système intégrés (`Dism.exe`, `netsh`, `Clear-RecycleBin`).
- **Sécurité** :
  - Ne modifie pas de services tiers, uniquement des composants Windows natifs.
  - N’envoie aucune donnée à l’extérieur en dehors du trafic standard Windows Update.

---

## Bonnes pratiques d’utilisation

- **Fréquence recommandée**
  - Poste utilisateur standard : 1 fois par mois ou après de grosses mises à jour.
  - Poste critique/serveur : uniquement après validation dans un environnement de test.

- **Avant l’exécution**
  - Sauvegarder les données importantes ou disposer d’un point de restauration système.
  - Fermer les applications non essentielles pour éviter des conflits de fichiers.

- **Après l’exécution**
  - Redémarrer la machine si des mises à jour système majeures ont été installées.
  - Vérifier l’espace disque libéré et le bon fonctionnement des applications métier critiques.

---

## FAQ

- **Q : Le script peut-il être utilisé sur un serveur de production ?**  
  **R :** Oui, mais il est fortement recommandé de le tester d’abord sur un environnement de pré-production et de valider l’impact des nettoyages et mises à jour.

- **Q : Est-ce que ce script remplace un outil de gestion de parc (SCCM, Intune, etc.) ?**  
  **R :** Non. Il s’agit d’un outil complémentaire, orienté maintenance ponctuelle et optimisation locale.

- **Q : Le script collecte-t-il ou envoie-t-il des données personnelles ?**  
  **R :** Non. Il ne fait qu’appeler des composants Windows natifs. Le seul trafic réseau est celui de Windows Update vers les serveurs Microsoft.

---

## Dépannage

- **Erreur de politique d’exécution (ExecutionPolicy)**  
  - Lancer PowerShell en tant qu’administrateur.
  - Exécuter :  
    ```powershell
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
    ```

- **Échec des commandes DISM**
  - Vérifier que vous êtes connecté avec un compte administrateur.
  - Vérifier l’intégrité du système avec :  
    ```powershell
    sfc /scannow
    ```
  - Puis relancer le script.

- **Les mises à jour ne se téléchargent pas**
  - Vérifier la connectivité Internet et les éventuels proxys/pare-feu.
  - S’assurer qu’aucune GPO ne réapplique une configuration WSUS restrictive après redémarrage.

## Personnalisation

Vous pouvez adapter le script selon vos besoins :

- **Cibles à nettoyer**  
  Dans `deploy.ps1`, la liste `$Targets` peut être modifiée pour ajouter ou retirer des dossiers.

- **Comportement des mises à jour**
  - Forcer l’installation sans confirmation utilisateur.
  - Filtrer différemment les mises à jour recherchées (critères `IsInstalled`, `IsHidden`, etc.).

- **Journalisation**
  - Ajouter une redirection vers un fichier log (`Out-File`, `Tee-Object`) pour tracer les opérations en environnement de production.

---

## Roadmap

- [ ] Ajout d’une option **mode silencieux** (aucune interaction utilisateur).
- [ ] Génération automatique d’un **rapport HTML/CSV** (taille avant/après, liste des mises à jour installées, etc.).
- [ ] Paramètres avancés via **fichier de configuration** (`.json` / `.psd1`).
- [ ] Intégration possible dans un scénario **CI/CD** ou un outil de déploiement (SCCM, Intune, etc.).

---

## Licence

Ce projet est proposé sous licence **MIT**.  
Adaptez cette section en fonction de la licence que vous souhaitez utiliser et ajoutez idéalement un fichier `LICENSE` à la racine du dépôt.

## Support & Contributions

Les contributions sont les bienvenues :

- **Issues** : pour signaler un bug ou demander une amélioration.
- **Pull Requests** : pour proposer des améliorations (nouvelles options, logs, compatibilité accrue, etc.).
