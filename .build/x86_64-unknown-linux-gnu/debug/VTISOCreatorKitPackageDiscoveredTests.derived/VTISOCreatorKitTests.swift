import XCTest
@testable import VTISOCreatorKitTests

fileprivate extension VTISOCreatorKitTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__VTISOCreatorKitTests = [
        ("testAddExtraRejectsDuplicateIDs", testAddExtraRejectsDuplicateIDs),
        ("testAllSixLayoutsEncode", testAllSixLayoutsEncode),
        ("testBackgroundIsSourceOfTruthForMenuBackground", testBackgroundIsSourceOfTruthForMenuBackground),
        ("testBuildsMinimalPortableVTISO", testBuildsMinimalPortableVTISO),
        ("testBuildsToOutputURLThatDoesNotExistYet", testBuildsToOutputURLThatDoesNotExistYet),
        ("testCustomListMinMaxItems", testCustomListMinMaxItems),
        ("testDeclaredBucketPathIsUsed", testDeclaredBucketPathIsUsed),
        ("testEnforcesTextMaxLength", testEnforcesTextMaxLength),
        ("testExistingOutputIsReplaced", testExistingOutputIsReplaced),
        ("testFallbackBucketPathWhenNoMatchingDefinition", testFallbackBucketPathWhenNoMatchingDefinition),
        ("testFileSchemaValidatedAsPathString", testFileSchemaValidatedAsPathString),
        ("testHexRegex", testHexRegex),
        ("testImportedClientJSONWrittenBackVerbatim", testImportedClientJSONWrittenBackVerbatim),
        ("testManifestAtArchiveRootWithNoWrappingFolder", testManifestAtArchiveRootWithNoWrappingFolder),
        ("testPathValidatorRejectsTraversal", testPathValidatorRejectsTraversal),
        ("testRecursiveItemSchemaValidation", testRecursiveItemSchemaValidation),
        ("testRejectsClientValuesWithoutExtension", testRejectsClientValuesWithoutExtension),
        ("testRejectsDuplicateBucketIDsAndPaths", testRejectsDuplicateBucketIDsAndPaths),
        ("testRejectsDuplicateVideoID", testRejectsDuplicateVideoID),
        ("testRejectsEmptyClientId", testRejectsEmptyClientId),
        ("testRejectsEmptyTitleAndCreatorName", testRejectsEmptyTitleAndCreatorName),
        ("testRejectsInvalidHexColor", testRejectsInvalidHexColor),
        ("testRejectsInvalidSelectDefault", testRejectsInvalidSelectDefault),
        ("testRejectsInvalidSelectOption", testRejectsInvalidSelectOption),
        ("testRejectsNonVTISOOutputExtension", testRejectsNonVTISOOutputExtension),
        ("testRejectsPerVideoSharedMisuse", testRejectsPerVideoSharedMisuse),
        ("testRejectsUnknownFieldIDs", testRejectsUnknownFieldIDs),
        ("testRejectsUnknownVideoIDInPerVideoValues", testRejectsUnknownVideoIDInPerVideoValues),
        ("testRejectsUnsafeBucketPaths", testRejectsUnsafeBucketPaths),
        ("testRejectsUnsupportedMinRuntime", testRejectsUnsupportedMinRuntime),
        ("testRejectsUnsupportedSchemaPrimitive", testRejectsUnsupportedSchemaPrimitive),
        ("testRequiredPerVideoTextValidatedPerVideo", testRequiredPerVideoTextValidatedPerVideo),
        ("testRequiredPerVideoUpload", testRequiredPerVideoUpload),
        ("testStableDiscIdAcrossRepeatedBuilds", testStableDiscIdAcrossRepeatedBuilds),
        ("testTempDirectoriesCleanedUpAfterFailedBuild", testTempDirectoriesCleanedUpAfterFailedBuild),
        ("testUploadRejectsMultipleWhenSingleOnly", testUploadRejectsMultipleWhenSingleOnly),
        ("testUploadRejectsOversizedFile", testUploadRejectsOversizedFile),
        ("testUploadValidatesAllowedTypes", testUploadValidatesAllowedTypes)
    ]
}
@available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
func __VTISOCreatorKitTests__allTests() -> [XCTestCaseEntry] {
    return [
        testCase(VTISOCreatorKitTests.__allTests__VTISOCreatorKitTests)
    ]
}