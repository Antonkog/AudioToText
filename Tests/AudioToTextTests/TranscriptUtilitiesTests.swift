import Testing
@testable import AudioToText

struct TranscriptUtilitiesTests {
    @Test func cleanedJoinsFragmentsAndNormalizesWhitespace() {
        let result = TranscriptUtilities.cleaned([" Hello   world ", " This\nis a test. "])
        #expect(result == "Hello world This is a test.")
    }

    @Test func safeBaseNameRemovesFileSystemPunctuation() {
        #expect(TranscriptUtilities.safeBaseName("Talk: part/one?") == "Talk- part-one")
    }
}
