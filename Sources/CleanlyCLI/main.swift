import CleanlyCore
import Darwin

let status = CleanlyApplication().run(Array(CommandLine.arguments.dropFirst()))
exit(status)
