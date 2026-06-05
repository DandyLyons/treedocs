import ArgumentParser

struct TreeDocs: ParsableCommand {
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

@main
enum TreeDocsMain {
    static func main() {
        TreeDocs.main(rewrittenArguments())
    }

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
