# gimme my vim
package "vim"

# use nginx in front of rok4, fastcgi backed
package "nginx"

# install rok4 and configure it to use the demo dataset
include_recipe "rok4"
include_recipe "rok4::setup"
include_recipe "rok4::dataset"

# nginx site for rok4 via fastcgi
cookbook_file "/etc/nginx/sites-available/rok4" do
  source "rok4.conf"
  mode "644"
  action :create_if_missing
end

# enable rok4 site
link "/etc/nginx/sites-enabled/rok4" do
    to "/etc/nginx/sites-available/rok4"
end

# restart nginx for the rok site to be available
service "nginx" do
  action :restart
end

# stop and start rok4 server
# TODO : make a rok4 LWRP
rok4binary = node['rok4']['binary'].split("/").last
rok4command = "/sbin/start-stop-daemon -b --name rok4 --exec #{node['rok4']['binary']} --start -- -f #{node['rok4']['config']['server_file']}"
rok4checkstatuscommand = "/sbin/start-stop-daemon -b --name rok4 --exec #{node['rok4']['binary']} --start -- -f #{node['rok4']['config']['server_file']}"

log "rok4 binary  : #{rok4binary}"
log "rok4 command : #{rok4command}"

# note1 : don't know if this is the right way, but it works :P
# note2 : only run the daemon if it is not already running (i.e. status=0)
bash "run rok4" do
    code <<-EOF
    set -x
    if [ "0" -ne "$(#{rok4checkstatuscommand})" ]
        then
            #{rok4command}
        else
            echo "Rok4 already running with pid $(pgrep #{rok4binary})"
    fi
    EOF
end
