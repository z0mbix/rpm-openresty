#!/usr/bin/env bash
#
# Create a RPM package for OpenResty

set -e
set -o pipefail ]]
[[ "$TRACE" ]] && set -x

usage() {
  echo "Usage example:"
  echo "$ VERSION=1.7.7.1 ITERATION=2 $0"
}

if [[ -z $VERSION ]] || [[ -z $ITERATION ]]; then
  usage
  exit 1
fi

which fpm >/dev/null 2>&1 || exit 3

dist_ver=$(grep -Eo '[0-9.]{1,}' /etc/redhat-release)
dist_major_ver=${dist_ver:0:1}
download_url="http://openresty.org/download/ngx_openresty-${VERSION}.tar.gz"
install_dir='/tmp/openresty'
pkg_name='openresty'
rpm_dir='/vagrant' # Where to save the RPM
download_dir='/tmp'
declare -a pkgs=(readline-devel pcre-devel openssl-devel rpm-build rpmdevtools)
pkg="${pkg_name}-${VERSION}-${ITERATION}.$(arch).rpm"
git_root=`git rev-parse --show-toplevel`
cd $git_root

if [[ -f ${rpm_dir}/${pkg} ]]; then
  echo "Package ${rpm_dir}/${pkg} already exists!"
  exit 4
fi

for pkg in ${pkgs[@]}; do
  if ! rpm -q $pkg >/dev/null; then
    echo "Installing package: $pkg"
    sudo yum install -y -q $pkg
  fi
done

if [[ ! -f ${download_dir}/ngx_openresty-${VERSION}.tar.gz ]]; then
  curl $download_url -o ${download_dir}/ngx_openresty-${VERSION}.tar.gz
fi

if [[ ! -f ${download_dir}/ngx_openresty-${VERSION}.tar.gz ]]; then
  echo "Could not download ngx_openresty-${VERSION}.tar.gz!"
  exit 1
fi

[[ -d $install_dir ]] || mkdir $install_dir

mkdir -p ${install_dir}/var/cache/openresty/{client,proxy,fastcgi,uwsgi,scgi}_temp

if [[ $dist_major_ver == '6' ]]; then
  mkdir -p ${install_dir}/etc/init.d
  cp openresty.init ${install_dir}/etc/init.d/openresty
  chmod 755 ${install_dir}/etc/init.d/openresty
elif [[ $dist_major_ver == '7' ]]; then
  mkdir -p ${install_dir}/usr/lib/systemd/system
  cp openresty.service ${install_dir}/usr/lib/systemd/system/
else
  echo "OS version \"${dist_ver}\" unknown!"
  exit 1
fi

if [[ ! -d ngx_openresty-${VERSION} ]]; then
  tar xzvf ${download_dir}/ngx_openresty-${VERSION}.tar.gz
fi

cd ngx_openresty-${VERSION}

./configure \
  --with-luajit \
  --prefix=/opt/openresty \
  --sbin-path=/usr/sbin/openresty \
  --conf-path=/etc/openresty/openresty.conf \
  --error-log-path=/var/log/openresty/error.log \
  --http-log-path=/var/log/openresty/access.log \
  --pid-path=/var/run/openresty.pid \
  --lock-path=/var/run/openresty.lock \
  --http-client-body-temp-path=/var/cache/openresty/client_temp \
  --http-proxy-temp-path=/var/cache/openresty/proxy_temp \
  --http-fastcgi-temp-path=/var/cache/openresty/fastcgi_temp \
  --http-uwsgi-temp-path=/var/cache/openresty/uwsgi_temp \
  --http-scgi-temp-path=/var/cache/openresty/scgi_temp \
  --user=openresty \
  --group=openresty

make
make install DESTDIR=$install_dir

mkdir -p ${install_dir}/etc/openresty/conf.d

fpm \
  --verbose \
  -s dir \
  -t rpm \
  -C $install_dir \
  --url 'http://openresty.org/' \
  --package $rpm_dir \
  --name $pkg_name \
  --maintainer 'z0mbix (zombie@zombix.org)' \
  --version $VERSION \
  --iteration $ITERATION \
  --epoch 1 \
  --description "OpenResty $VERSION" \
  --before-install "../pre-install" \
  --after-install "../post-install" \
  --depends "pcre" \
  --depends "readline" \
  --depends "openssl" \
  --rpm-user root \
  --rpm-group root \
  --config-files /etc/openresty/openresty.conf \
  --directories /etc/openresty \
  --directories /opt/openresty \
  --directories /var/cache/openresty \
  --directories /var/log/openresty \
  var etc usr opt

rm -rf $install_dir

