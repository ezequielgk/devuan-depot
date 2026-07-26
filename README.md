# rox-apt-repo

Repositorio APT personal. Los workflows en `.github/workflows/` compilan
proyectos (propios o de terceros) y publican los `.deb` resultantes en la
rama `gh-pages`, que se sirve vía GitHub Pages como repositorio APT.

## Instalación (en Devuan/Debian)

```bash
curl -fsSL https://TU_USUARIO.github.io/REPO_NAME/public.asc \
  | sudo gpg --dearmor -o /usr/share/keyrings/rox-apt-repo.gpg

echo "deb [signed-by=/usr/share/keyrings/rox-apt-repo.gpg] https://TU_USUARIO.github.io/REPO_NAME trixie main" \
  | sudo tee /etc/apt/sources.list.d/rox-apt-repo.list

sudo apt update
sudo apt install <paquete>
```
