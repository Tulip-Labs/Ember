#!/bin/sh
# Makes the apt and dnf repositories served from GitHub Pages:
#   update-repo.sh <folder with the .deb and .rpm> <output folder>
# With the secret REPO_GPG_KEY (an armored private key, no passphrase) the
# repositories and packages are signed and the key is published beside them;
# without it the repositories are unsigned (the files still come over HTTPS).
set -eu
in=$1
out=$2
URL=${PAGES_URL:-https://tulip-labs.github.io/Ember}
rm -rf "$out"
mkdir -p "$out/deb/pool/main" "$out/rpm"
cp "$in"/*.deb "$out/deb/pool/main/"
cp "$in"/*.rpm "$out/rpm/"

signed=0
if [ -n "${REPO_GPG_KEY:-}" ]; then
	export GNUPGHOME
	GNUPGHOME=$(mktemp -d)
	printf '%s\n' "$REPO_GPG_KEY" | gpg --batch --import
	KEYID=$(gpg --list-secret-keys --with-colons | awk -F: '/^sec/ {print $5; exit}')
	gpg --armor --export "$KEYID" > "$out/ember-shell.asc"
	gpg --export "$KEYID" > "$out/ember-shell.gpg"
	signed=1
fi

# apt: one suite (stable), one component (main)
(
	cd "$out/deb"
	for arch in amd64 arm64; do
		mkdir -p "dists/stable/main/binary-$arch"
		dpkg-scanpackages --arch "$arch" pool/ > "dists/stable/main/binary-$arch/Packages"
		gzip -9kf "dists/stable/main/binary-$arch/Packages"
	done
	apt-ftparchive -o APT::FTPArchive::Release::Origin="Tulip Labs" -o APT::FTPArchive::Release::Label="Ember" \
		-o APT::FTPArchive::Release::Suite=stable -o APT::FTPArchive::Release::Codename=stable \
		-o APT::FTPArchive::Release::Architectures="amd64 arm64" -o APT::FTPArchive::Release::Components=main \
		release dists/stable > dists/stable/Release
	if [ $signed = 1 ]; then
		gpg --batch --yes --default-key "$KEYID" --clearsign -o dists/stable/InRelease dists/stable/Release
		gpg --batch --yes --default-key "$KEYID" -abs -o dists/stable/Release.gpg dists/stable/Release
	fi
)

# dnf / zypper
if [ $signed = 1 ]; then
	echo "%_gpg_name $KEYID" > ~/.rpmmacros
	rpm --addsign "$out"/rpm/*.rpm
fi
createrepo_c -q "$out/rpm"
if [ $signed = 1 ]; then
	gpg --batch --yes --default-key "$KEYID" --detach-sign --armor "$out/rpm/repodata/repomd.xml"
	check="gpgcheck=1
repo_gpgcheck=1
gpgkey=$URL/ember-shell.asc"
	apt_line="deb [signed-by=/usr/share/keyrings/ember-shell.gpg] $URL/deb stable main"
	apt_setup="curl -fsSL $URL/ember-shell.gpg | sudo tee /usr/share/keyrings/ember-shell.gpg >/dev/null
echo \"$apt_line\" | sudo tee /etc/apt/sources.list.d/ember-shell.list"
else
	check="gpgcheck=0
repo_gpgcheck=0"
	apt_line="deb [trusted=yes] $URL/deb stable main"
	apt_setup="echo \"$apt_line\" | sudo tee /etc/apt/sources.list.d/ember-shell.list"
fi
cat > "$out/rpm/ember-shell.repo" <<REPO
[ember-shell]
name=Ember
baseurl=$URL/rpm
enabled=1
metadata_expire=1h
$check
REPO
cp "$out/rpm/ember-shell.repo" "$out/ember-shell.repo"

cat > "$out/index.html" <<HTML
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Ember packages</title>
<style>body{font:16px/1.5 system-ui,sans-serif;max-width:46rem;margin:2rem auto;padding:0 1rem;color:#241f4e;background:#fdfaf3}
pre{background:#f1ecfb;padding:.8rem 1rem;border-radius:10px;overflow-x:auto}h1{font-size:1.6rem}</style></head><body>
<h1>Ember for Linux</h1>
<p>Packages for Ember, the full-screen home for niri by Tulip Labs. After installing, run <code>ember</code> once inside niri. Downloads and source:
<a href="https://github.com/Tulip-Labs/Ember/releases">GitHub releases</a>.</p>
<h2>Debian, Ubuntu, Linux Mint</h2>
<pre>$apt_setup
sudo apt update && sudo apt install ember-shell</pre>
<h2>Fedora</h2>
<pre>sudo dnf config-manager addrepo --from-repofile=$URL/ember-shell.repo
sudo dnf install ember-shell</pre>
<h2>openSUSE</h2>
<pre>sudo zypper addrepo $URL/ember-shell.repo
sudo zypper install ember-shell</pre>
<h2>Fedora Atomic (Silverblue, Kinoite)</h2>
<pre>sudo curl -fsSLo /etc/yum.repos.d/ember-shell.repo $URL/ember-shell.repo
rpm-ostree install ember-shell</pre>
</body></html>
HTML
touch "$out/.nojekyll"
find "$out" -maxdepth 3 | sort
