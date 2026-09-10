import Foundation

/// Umbrella namespace + version marker for the ImportKit module.
///
/// ImportKit is pure, UI-free logic: it loads declarative YAML import specs
/// (the same format used by the Python `statement-importer` tool), evaluates
/// their CEL-subset field expressions against CSV rows, and produces
/// `NormalizedRow` values ready to become transactions.
public enum ImportKit {
    public static let version = "0.1.0"
}
