class Hook
  require File.expand_path(File.join(File.dirname(__FILE__),  "git_world"))
  require 'open3'
  include Open3



  # Set this to true if you want warnings to stop your commit
  def initialize(stop_on_warnings = false)
    @files_to_watch = /(.+\.(e?rb|task|rake|thor|prawn)|[Rr]akefile|[Tt]horfile)/

    @color_regexp = /\e\[(\d+)m/
    @rb_regexp     = /\.(rb|rake|task|prawn)\z/
    @erb_regexp   = /\.erb\z/
    @js_regexp   = /\.js\z/
  
    @rb_warning_regexp  = /[0-9]+:\s+warning:/
    @erb_invalid_regexp = /invalid\z/
    @stop_on_warnings = stop_on_warnings

  # In case of Rubinius use without RVM
  # @compiler_ruby = `which rbx`.strip
  # @compiler_ruby = `which ruby`.strip if compiler_ruby.length == 0 
    @compiler_ruby = `which ruby`.strip

    @world = GitWorld.new(stop_on_warnings)
    @changed_ruby_files = `git diff-index --name-only --cached HEAD`.split("\n").select{ |file| file =~ @files_to_watch }.map(&:chomp)
  end

  def each_changed_file
    if @world.continue?
      @changed_ruby_files.each do |file|
        yield file if File.readable?(file)
      end
    end
  end

  def check_syntax
    each_changed_file do |file|
      if file =~ @rb_regexp
        popen3("#{@compiler_ruby} -wc #{file}") do |stdin, stdout, stderr|
          stderr.read.split("\n").each do |line|
            line =~ @rb_warning_regexp ? @world.warnings << line : @world.errors << line 
          end
        end
        end
    end
  end

  def check_erb
    each_changed_file do |file|
      if file =~ @erb_regexp
        popen3("rails-erb-check #{file}") do |stdin, stdout, stderr|
          @world.errors.concat stdout.read.split("\n").map{|line| "#{file} => invalid ERB syntax" if line.gsub(@color_regexp, '') =~ @erb_invalid_regexp}.compact
        end
      end
    end
  end

  def check_best_practices
    each_changed_file do |file|
      if file =~ @rb_regexp or file =~ @erb_regexp
        popen3("rails_best_practices #{file}") do |stdin, stdout, stderr|
          @world.warnings.concat stdout.read.split("\n")
        end
      end
    end
  end

  # Maybe need options for different file types :rb :erb :js
  def warnning_on(string)
    each_changed_file do |file|
      popen3("fgrep console.log #{file}") do |stdin, stdout, stderr|
        err = stdout.read
        if err.split("\n").size > 0 
          @world.warnings << "#{string} in #{file}:"
        end
      end
    end
  end

  def results
    status = 0
    if @world.errors.size > 0 
      status = 1
      puts "ERRORS:\n"
      puts @world.errors.join("\n\n")
    end

    if @world.warnings.size > 0 
      status = 1 if @stop_on_warnings

      puts "Warnings: \n"
      puts @world.warnings.join("\n\n")
    end
    return status
  end
end