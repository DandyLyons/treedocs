import ArgumentParser

/// Defines the root `treedocs` command.
///
/// `TreeDocs` is the top-level ArgumentParser command. It registers every supported subcommand and
/// owns the command metadata shown in help output.
struct TreeDocs: ParsableCommand {
    /// The command name, abstract, and available subcommands for the CLI.
    static let configuration = CommandConfiguration(
        commandName: "treedocs",
        abstract: "Generate and maintain a YAML-based architectural map of a repository.",
        subcommands: [
            InitCommand.self,
            SyncCommand.self,
            CheckCommand.self,
            ShowCommand.self,
            InspectCommand.self,
            UpdateCommand.self,
            ConfigCommand.self,
            PromptsCommand.self,
            LsCommand.self,
            PathCommand.self,
        ]
    )
}

/// Starts the command-line application.
///
/// `TreeDocsMain` performs a small argument normalization step before handing control to
/// ArgumentParser. This preserves the explicit command surface while allowing `treedocs <path>` to
/// behave like `treedocs show <path>`.
@main
enum TreeDocsMain {
    /// Runs the root command.
    ///
    /// Command-line arguments are rewritten before dispatch so the shorthand path form is accepted by
    /// the same parser configuration as explicit commands.
    static func main() {
        TreeDocs.main(rewrittenArguments())
    }

    /// Rewrites shorthand path arguments into explicit `show` invocations.
    ///
    /// Only the first non-option argument is considered for rewriting. Existing commands, help flags,
    /// and unknown option-like arguments are left untouched so ArgumentParser can handle them normally.
    ///
    /// - Returns: The command-line arguments that should be passed to ArgumentParser.
    private static func rewrittenArguments() -> [String] {
        var arguments = Array(CommandLine.arguments.dropFirst())
        let commands: Set<String> = [
            "init",
            "sync",
            "check",
            "show",
            "inspect",
            "update",
            "config",
            "prompts",
            "ls",
            "path",
            "help",
        ]
        guard let pathIndex = firstPathArgumentIndex(in: arguments, commands: commands) else {
            return arguments
        }

        arguments.insert("show", at: pathIndex)
        return arguments
    }

    /// Finds the argument index for an implicit `show` path.
    ///
    /// The scanner skips repository path options because their following value is not a command target.
    /// It returns `nil` as soon as it sees an explicit command, a help flag, or an unsupported option.
    ///
    /// - Parameters:
    ///   - arguments: The arguments after dropping the executable path.
    ///   - commands: Command names that should disable shorthand rewriting.
    /// - Returns: The index of the bare path argument to rewrite, or `nil` when no rewrite is needed.
    private static func firstPathArgumentIndex(in arguments: [String], commands: Set<String>) -> Int? {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if commands.contains(argument) || argument == "--help" || argument == "-h" {
                return nil
            }
            if argument == "--path" || argument == "-p" {
                index += 2
                continue
            }
            if argument.hasPrefix("--path=") {
                index += 1
                continue
            }
            if argument.hasPrefix("-") {
                return nil
            }
            return index
        }
        return nil
    }
}
