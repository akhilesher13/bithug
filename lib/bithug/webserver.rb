require "bithug"
require "bithug/big_band"
require "digest/md5"
require "chronic_duration"
require "haml"

module Bithug
  class Webserver < Sinatra::BigBand
    enable :sessions

    helpers do

      def user_named(name)
        Bithug::User.find(:name => name).first
      end

      def user
        @user ||= user_named(params[:username])
      end

      def current_user
        user_named request.env['REMOTE_USER']
      end

      def current_user?
        user == current_user
      end

      def toggle_follow
        "#{"un" if current_user.following? user}follow"
      end

      def toggle_public
  if repo.public?
    "Mark private"
  else
    "Make public"
  end
      end

      def gravatar_url(mail, size, default)
        "http://www.gravatar.com/avatar/#{Digest::MD5::new.update(mail.to_s)}?s=#{size}&d=#{default}"
      end

      def gravatar(mail, size = 80, default = "wavatar")
        "<img src='#{gravatar_url(mail, size, default)}' alt='' width='#{size}' height='#{size}' class='gravatar'>"
      end

      def repo_named(name)
        Bithug::Repository.find(:name => name).first
      end

      def repo
        return unless user
        repo = repo_named(user.name / params[:repository])
        repo if repo and repo.check_access_rights(current_user)
      rescue Bithug::ReadAccessDeniedError
        nil
      end

      def owned?
        repo.owner == current_user
      end

      def title
        Bithug.title
      end

      def log_entries(num = 30)
        current_user.following.all.compact.collect do |u|
          u.recent_activity(num)
        end.flatten.sort_by { |i| i.date_time }.reverse[0..num]
      end

      def commit_entries(num = 5)
  repo.recent_activity(num).reverse
      end

      def time_ago(time)
        ChronicDuration.output(Time.now.to_i - time.to_i).to_s << " ago"
      end

    end

    def follow_unfollow
      pass unless user
      yield unless current_user?
      current_user.save
      redirect "/#{params[:username]}"
    end

    get("/") { haml :dashboard }

    get "/:username/?" do
      # user.commits.recent(20)
      # user.network.recent
      # user.forks.recent(5)
      # user.rights.recent

      pass unless user
      haml :user
    end

    get("/:username/follow") do
      follow_unfollow { current_user.follow(user) }
    end

    get("/:username/unfollow") do
      follow_unfollow { current_user.unfollow(user) }
    end

    get "/:username/new" do
      pass unless current_user?
      haml :new_repository
    end

    post "/:username/new" do
      pass unless current_user?
      vcs = params[:vcs] || "git"
      unless vcs == "svn" && !params[:remote]
        reponame = params[:repo_name]
        Repository.create(:name => reponame, :owner => user, :vcs => vcs, :remote => params[:remote])
        redirect "/#{user.name}/#{reponame}"
      else
        redirect "/:username/new"
      end
    end

    get "/:username/settings" do
      pass unless current_user?
      haml :settings
    end

    post '/:username/settings' do
      pass unless current_user?
      user.real_name = params["real_name"]
      user.email = params["email"]
      user.save
      redirect "/#{user.name}/settings"
    end

    get "/:username/delete_key/:id" do
      pass unless current_user?
      key = Bithug::Key[params[:id]]
      key.remove(user) if user.ssh_keys.include? key
      redirect "/#{user.name}/settings"
    end

    post "/:username/add_key" do
      pass unless current_user?
      Bithug::Key.add :user => user, :name => params["name"], :value => params["value"]
      redirect "/#{user.name}/settings"
    end

    get "/:username/:repository/?" do
      pass unless repo
      # repo.tree <- returns a nested hash of the (w)hole repository tree
      haml :repository, {}, :commit_spec => "master", :tree => repo.tree("master"), :is_subtree => false
    end

    get "/:username/:repository/admin/?" do
      pass unless repo and current_user?
      # repo.tree <- returns a nested hash of the (w)hole repository tree
      haml :repository_settings, {}, :commit_spec => "master", :tree => repo.tree("master"), :is_subtree => false
    end

    post "/:username/:repository/admin/?" do
      pass unless repo and current_user?
      # repo.tree <- returns a nested hash of the (w)hole repository tree
      repo.rename_repository(params[:name])
      redirect "/#{user.name}/#{params[:name]}/admin"
    end

    get "/:username/:repository/delete/?" do
      pass unless repo and current_user?
      haml :confirmation, {}, :return_url => "/#{repo.name}",
   :message => "Are you sure you want to delete your repository #{repo.name}? This action cannot be undone!"
    end

    get "/:username/:repository/delete/confirmed" do
      pass unless repo and current_user?
      repo.remove
      redirect "/#{user.name}"
    end

    get "/:username/:repository/toggle_public?" do
      pass unless repo and current_user?
      repo.set_public(!repo.public?)
      redirect "/#{repo.name}/admin"
    end

    post "/:username/:repository/grant" do
      # epxects :read_or_write and :other_username
      pass unless repo and %w(w r).include? params[:read_or_write] and current_user? and user_named params[:other_username]
      user.grant_access :user => user_named(params[:other_username]), :repo => repo, :access => params[:read_or_write]
      redirect "/#{repo.name}/admin"
    end

    get "/:username/:repository/revoke/:read_or_write/:other_username" do
      pass unless repo and %w(w r).include? params[:read_or_write] and current_user? and user_named params[:other_username]
      user.revoke_access :user => user_named(params[:other_username]), :repo => repo, :access => params[:read_or_write]
      redirect "/#{repo.name}/admin"
    end

    get "/:username/:repository/fork" do
      pass unless repo
      repo.fork current_user
      redirect "/#{current_user.name}/#{params[:repository]}"
    end

    get "/:username/:repository/:commit_spec/?*/?" do
      pass unless repo
      commit_spec = "master" if params[:commit_spec].nil? or params[:commit_spec].empty?
      commit_spec ||= params[:commit_spec]
      tree = params["splat"].first.split("/").inject repo.tree(commit_spec) do |subtree, subpath|
        pass unless subtree.include? subpath
        subtree[subpath]
      end
      haml :repository, {}, :tree => tree, :is_subtree => !params["splat"].first.empty?, :commit_spec => params[:commit_spec]
    end

    get "/:username/:repository/admin" do
      pass unless repo
      haml :repository, :admin
    end

    get "/:username/feed" do
      pass unless current_user?
      content_type :rss
      haml :feed, :layout => false, :format => :xhtml
    end

    post "/:username/connect_to_twitter" do
      pass unless current_user?
      current_user.twitter_authorize(params[:pin])
      redirect "/#{current_user.name}/settings"
    end

    get "/:username/clear_twitter_connection" do
      pass unless current_user?
      current_user.twitter_clear_account
      redirect "/#{current_user.name}/settings"
    end

  end
end
