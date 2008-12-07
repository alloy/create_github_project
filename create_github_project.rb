require 'rubygems'
require 'mechanize'

username = 'alloy'
password = '*****'

repository = 'remote-test'
description = 'A remote test'
users = %w{ alloy manfred }

checkout = File.expand_path('~/tmp/remote-test')

setup = lambda do
  github = GitHub.new(username, password)
  project = github.create_project(repository, description)
  users.each { |user| project.add_user(user) }
  project.checkout(checkout)
  project.enable_service 'Campfire',
    :subdomain => 'fingertips', :email => 'github@fngtps.com', :password => 'foo', :room => 'Office', :ssl => true
end

class GitHub
  def initialize(username, password)
    @username, @password = username, password
    @agent = WWW::Mechanize.new
    login
  end
  
  def login
    get url_for('/login')
    submit_form '/session', 'login' => @username, 'password' => @password
  end
  
  def create_project(repository, description)
    Project.create(@agent, @username, repository, description)
  end
  
  class Project
    def self.create(agent, username, repository, description)
      project = new(agent, username, repository, description)
      project.create
      project
    end
    
    def initialize(agent, username, repository, description)
      @agent, @username, @repository, @description = agent, username, repository, description
    end
    
    def create
      puts "Creating repository: #{@repository}"
      get url_for('/repositories/new')
      submit_form '/repositories',
        namespace_keys('repository', :name => @repository, :description => @description)
    end
    
    def add_user(username)
      puts "Adding user: #{username}"
      get url_for_action('/edit/collaborators')
      submit_form action_path('/edit/add_member'), 'member' => username
    end
    
    def enable_service(name, values)
      get url_for_action('/edit/hooks')
      submit_form(proc { |f| f.fields.any? { |field| field.name =~ /^#{name}\[/ } },
        namespace_keys('service', :name => name, :active => true).merge(namespace_keys(name, values)))
    end
    
    def checkout(path)
      puts "Creating clone and initial commit: #{path}"
      FileUtils.mkdir_p(path)
      File.open(File.join(path, 'README'), 'w') { |f| f.write @description }
      Dir.chdir(path) do
        `git init && git add . && git commit -m "Inital commit"`
        `git remote add origin git@github.com:#{@username}/#{@repository}.git`
        `git push origin master`
      end
    end
  end
  
  module ActionHelpers
    def url_for(path)
      "https://github.com#{path}"
    end
    
    def action_path(path)
      "/#{@username}/#{@repository}#{path}"
    end
    
    def url_for_action(path)
      url_for(action_path(path))
    end
    
    def get(url)
      p url
      @page = @agent.get(url)
      #p @page
    end
    
    def namespace_keys(namespace, hash)
      hash.inject({}) { |new_hash, (k, v)| new_hash["#{namespace}[#{k}]"] = v; new_hash }
    end
    
    def submit_form(action_or_proc, values)
      form = @page.forms.find(&(action_or_proc.is_a?(Proc) ? action_or_proc : proc { |f| f.action == action_or_proc }))
      p form
      values.each do |name, value|
        if value == true || value == false
          form.checkboxes.find { |c| c.name == name }.value = (value ? '1' : '0') # FIXME!
        else
          form.fields.find { |f| f.name == name }.value = value
        end
      end
      @page = @agent.submit(form, form.buttons.first)
      #p @page
    end
  end
  
  include ActionHelpers
  Project.send(:include, ActionHelpers)
end

setup.call