import Testing
@testable import PPSRSolo

struct CardBrandDetectionTests {
    @Test func detectsVisa() {
        #expect(CardBrand.detect("4111111111111111") == .visa)
        #expect(CardBrand.detect("4242424242424242") == .visa)
    }

    @Test func detectsMastercard() {
        #expect(CardBrand.detect("5500000000000004") == .mastercard)
        #expect(CardBrand.detect("2221000000000009") == .mastercard)
    }

    @Test func detectsAmex() {
        #expect(CardBrand.detect("340000000000009") == .amex)
        #expect(CardBrand.detect("370000000000002") == .amex)
    }

    @Test func detectsJCB() {
        #expect(CardBrand.detect("3530111333300000") == .jcb)
    }

    @Test func detectsDiscover() {
        #expect(CardBrand.detect("6011000000000004") == .discover)
        #expect(CardBrand.detect("6500000000000002") == .discover)
    }

    @Test func detectsDinersClub() {
        #expect(CardBrand.detect("36000000000008") == .dinersClub)
        #expect(CardBrand.detect("38000000000006") == .dinersClub)
    }

    @Test func detectsUnionPay() {
        #expect(CardBrand.detect("6200000000000005") == .unionPay)
    }

    @Test func unknownForInvalid() {
        #expect(CardBrand.detect("9999999999999999") == .unknown)
        #expect(CardBrand.detect("") == .unknown)
    }
}

@MainActor
struct CardParsingTests {
    @Test func parsesPipeFormat() {
        let cards = PPSRCard.smartParse("4111111111111111|12|28|123")
        #expect(cards.count == 1)
        #expect(cards.first?.number == "4111111111111111")
        #expect(cards.first?.expiryMonth == "12")
        #expect(cards.first?.expiryYear == "28")
        #expect(cards.first?.cvv == "123")
        #expect(cards.first?.brand == .visa)
    }

    @Test func parsesColonFormat() {
        let cards = PPSRCard.smartParse("5500000000000004:06:25:456")
        #expect(cards.count == 1)
        #expect(cards.first?.number == "5500000000000004")
        #expect(cards.first?.brand == .mastercard)
    }

    @Test func parsesMultipleLines() {
        let input = """
        4111111111111111|12|28|123
        5500000000000004|06|25|456
        """
        let cards = PPSRCard.smartParse(input)
        #expect(cards.count == 2)
    }

    @Test func skipsInvalidLines() {
        let input = """
        4111111111111111|12|28|123
        invalid line
        """
        let cards = PPSRCard.smartParse(input)
        #expect(cards.count == 1)
    }
}

@MainActor
struct PPSRCardModelTests {
    @Test func cardInitialization() {
        let card = PPSRCard(number: "4111111111111111", expiryMonth: "12", expiryYear: "28", cvv: "123")
        #expect(card.brand == .visa)
        #expect(card.status == .untested)
        #expect(card.totalTests == 0)
        #expect(card.successRate == 0)
        #expect(card.binPrefix == "411111")
        #expect(card.formattedExpiry == "12/28")
        #expect(card.pipeFormat == "4111111111111111|12|28|123")
    }

    @Test func recordResult() {
        let card = PPSRCard(number: "4111111111111111", expiryMonth: "12", expiryYear: "28", cvv: "123")
        card.recordResult(success: true, vin: "TEST123", duration: 5.0)
        #expect(card.totalTests == 1)
        #expect(card.successCount == 1)
        #expect(card.successRate == 1.0)

        card.recordResult(success: false, vin: "TEST456", duration: 3.0, error: "Declined")
        #expect(card.totalTests == 2)
        #expect(card.successCount == 1)
        #expect(card.failureCount == 1)
        #expect(card.successRate == 0.5)
    }

    @Test func sanitizesTwoDigitMonth() {
        let card = PPSRCard(number: "4111111111111111", expiryMonth: "1", expiryYear: "28", cvv: "123")
        #expect(card.expiryMonth == "01")
    }
}

struct BatchResultTests {
    @Test func calculatesAlivePercentage() {
        let result = BatchResult(working: 3, dead: 5, requeued: 2, total: 10)
        #expect(result.alivePercentage == 30)
    }

    @Test func handlesZeroTotal() {
        let result = BatchResult(working: 0, dead: 0, requeued: 0, total: 0)
        #expect(result.alivePercentage == 0)
    }
}

struct VINGeneratorTests {
    @Test func generatesValidVIN() {
        let vin = PPSRVINGenerator.generate()
        #expect(!vin.isEmpty)
        #expect(vin.count >= 6)
    }

    @Test func generatesUniqueVINs() {
        let vin1 = PPSRVINGenerator.generate()
        let vin2 = PPSRVINGenerator.generate()
        #expect(vin1 != vin2)
    }
}

@MainActor
struct DebugLogTests {
    @Test func logEntryFormatting() {
        let entry = DebugLogEntry(
            category: .ppsr,
            level: .info,
            message: "Test message",
            detail: "Some detail",
            sessionId: "sess_123"
        )
        #expect(entry.category == .ppsr)
        #expect(entry.level == .info)
        #expect(entry.message == "Test message")
        #expect(entry.detail == "Some detail")
        #expect(entry.sessionId == "sess_123")
        #expect(entry.compactLine.contains("Test message"))
        #expect(entry.exportLine.contains("sess_123"))
    }

    @Test func logLevelComparison() {
        #expect(DebugLogLevel.trace < DebugLogLevel.debug)
        #expect(DebugLogLevel.debug < DebugLogLevel.info)
        #expect(DebugLogLevel.info < DebugLogLevel.success)
        #expect(DebugLogLevel.success < DebugLogLevel.warning)
        #expect(DebugLogLevel.warning < DebugLogLevel.error)
        #expect(DebugLogLevel.error < DebugLogLevel.critical)
    }
}

struct NordKeyProfileTests {
    @Test func profileKeysExist() {
        #expect(!NordKeyProfile.nick.hardcodedAccessKey.isEmpty)
        #expect(!NordKeyProfile.poli.hardcodedAccessKey.isEmpty)
        #expect(NordKeyProfile.nick.hardcodedAccessKey != NordKeyProfile.poli.hardcodedAccessKey)
    }
}
