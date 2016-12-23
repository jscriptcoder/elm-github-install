require_relative './resolver'

module ElmInstall
  # This class is responsible getting a solution for the `elm-package.json`
  # file and populating the `elm-stuff` directory with the packages and
  # writing the `elm-stuff/exact-dependencies.json`.
  class Installer
    extend Forwardable

    # Initializes a new installer with the given options.
    def initialize(options = { verbose: false })
      @options = options
      @cache = Cache.new
    end

    # Executes the installation
    #
    # :reek:TooManyStatements { max_statements: 7 }
    def install
      puts 'Resolving packages...'
      resolver.add_constraints dependencies

      puts 'Solving dependencies...'
      begin
        populate_elm_stuff
      rescue
        @cache.clear
        resolver.add_constraints dependencies
        populate_elm_stuff
      end

      puts 'Saving index cache...'
      @cache.save

      puts 'Packages configured successfully!'
    end

    private

    # Populates the `elm-stuff` directory with the packages from
    # the solution.
    def populate_elm_stuff
      solution.each do |package, version|
        resolve_package package, version
      end

      write_exact_dependencies
    end

    # Resolves and copies a package and it's version to `elm-stuff/packages`
    # directory.
    #
    # :reek:TooManyStatements { max_statements: 9 }
    def resolve_package(package, version)
      package_name, package_path = Utils.package_version_path package, version

      matches = dependencies[package_name].to_s.match(/^(ref|branch):(.*)/)

      ref = (matches && matches[2]) || version
      @cache.repository(package).checkout(ref)

      version_str = ref == version ? ref : "#{ref}(#{version})"
      Utils.log_with_dot "#{package_name} - #{version_str}"

      return if Dir.exist?(package_path)

      copy_package package, package_path
    end

    # Copies the given package from it's repository to the given path.
    def copy_package(package, package_path)
      FileUtils.mkdir_p(package_path)
      FileUtils.cp_r(
        File.join(@cache.repository_path(package), '.'), package_path
      )
      FileUtils.rm_rf(File.join(package_path, '.git'))
    end

    # Writes the `elm-stuff/exact-dependencies.json` file.
    def write_exact_dependencies
      path = File.join('elm-stuff', 'exact-dependencies.json')
      File.binwrite(path, JSON.pretty_generate(exact_dependencies))
    end

    # Returns the exact dependencies from the solution.
    def exact_dependencies
      @exact_dependencies ||=
        solution.each_with_object({}) do |(key, value), memo|
          memo[GitCloneUrl.parse(key).path] = value
        end
    end

    # Returns the resolver to calculate the solution.
    def resolver
      @resolver ||= Resolver.new @cache
    end

    # Returns the solution for the given `elm-package.json` file.
    def solution
      @solution ||=
        Solve.it!(
          GraphBuilder.graph_from_cache(@cache, @options),
          resolver.constraints
        )
    end

    # Returns the dependencies from the `elm-package.json` file.
    def dependencies
      @dependencies ||=
        JSON.parse(File.read('elm-package.json'))['dependencies']
    end
  end
end
