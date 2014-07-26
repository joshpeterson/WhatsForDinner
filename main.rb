require 'rubygems'
require 'sinatra'
require 'data_mapper'
require 'openid'
require 'openid/store/filesystem'
require 'sanitize'

DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/development.db")

class Dinner
  include DataMapper::Resource  

  property :id,           Serial
  property :text,         String

  belongs_to :user
end

class User
  include DataMapper::Resource

  property :id,         Serial
  property :openid,     Text

  has n, :dinners
end

DataMapper.finalize

enable :sessions 

get '/' do
    dinners = get_dinners_for_user(session[:user])
    if !dinners.nil?
        dinners = dinners.shuffle
        @dinner = dinners[0]
        if @dinner.nil?
            redirect '/dinners'
        end
        erb :index, :layout => :layout_with_new_dinner
    else
        redirect '/login'
    end
end

post '/dinner/create' do
    user = get_user(session[:user])
    if !user.nil?
        if !params[:text].empty?
            add_dinner_for_user(user, Sanitize.clean(params[:text]))
        end
        redirect '/dinners'   
    else
        redirect '/login'
    end
end

get '/dinner/:id/delete' do
    dinners = get_dinners_for_user(session[:user])
    if !dinners.nil?
        @dinner = dinners.get(params[:id])
        if !@dinner.nil?
            erb :delete
        else
            redirect '/dinners'
        end
    else
        redirect '/login'
    end
end

delete '/dinner/:id' do
    dinners = get_dinners_for_user(session[:user])
    if !dinners.nil?
        if !dinners.get(params[:id]).nil?
            Dinner.get(params[:id]).destroy
        end
        redirect '/dinners'  
    else
        redirect '/login'
    end
end

get '/dinners' do
    @dinners = get_dinners_for_user(session[:user])
    if !@dinners.nil?
        erb :dinners, :layout => :layout_with_new_dinner
    else
        redirect '/login'
    end
end

get '/about' do
    erb :about, :layout => :layout_with_new_dinner
end

get '/logout' do
    session[:user] = nil
    redirect '/login'
end

get '/login' do    
    erb :login
end

post '/login/openid' do
    openid = params[:openid_identifier]
    begin
        oidreq = openid_consumer.begin(openid)
        rescue OpenID::DiscoveryFailure => why
        "Sorry, we couldn't find your identifier '#{openid}'"
    else
        redirect oidreq.redirect_url(root_url, root_url + "/login/openid/complete")
    end
end

get '/login/openid/complete' do
    oidresp = openid_consumer.complete(params, request.url)

    case oidresp.status
        when OpenID::Consumer::FAILURE
            "Sorry, we could not authenticate you with the identifier '{openid}'."
        when OpenID::Consumer::SETUP_NEEDED
            "Immediate request failed - Setup Needed"
        when OpenID::Consumer::CANCEL
            "Login cancelled."
        when OpenID::Consumer::SUCCESS
            openid = oidresp.identity_url
            user = User.first_or_create(:openid => openid)
            if user.nil?
                "Login error - unable to create user: " + oidresp.identity_url
            else
                session[:user] = user.openid
                redirect '/'
            end
    end
end

def openid_consumer
    @openid_consumer ||= OpenID::Consumer.new(session,
        OpenID::Store::Filesystem.new("#{File.dirname(__FILE__)}/tmp/openid"))  
end

def root_url
    request.url.match(/(^.*\/{2}[^\/]*)/)[1]
end

def logged_in?
   !session[:user].nil?
end

def get_user(openid)
    User.first(:openid => openid)
end

def get_dinners_for_user(openid)
    user = get_user(openid)
    if !user.nil?
        user.dinners
    end
end

def add_dinner_for_user(user, dinner)
    if user.dinners.empty? || user.dinners.index(dinner).nil?
        user.dinners << Dinner.create(:text => dinner)
        user.save
    end
end

DataMapper.auto_upgrade!
