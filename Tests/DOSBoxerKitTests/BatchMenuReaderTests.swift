import Testing
@testable import DOSBoxerKit

struct BatchMenuReaderTests {
    let boxing = """
        :menu\r
        @echo off\r
        cls\r
        echo Press 1 for ABC Wide World of Sports Boxing w/ SoundBlaster\r
        echo Press 2 for ABC Wide World of Sports Boxing w/ MT-32\r
        echo Press 3 to Quit\r
        choice /C:123 /N Please Choose:\r
        if errorlevel = 3 goto quit\r
        if errorlevel = 2 goto MT32\r
        if errorlevel = 1 goto SB16\r
        :SB16\r
        CONFIG -set "mididevice=default"\r
        copy .\\sb16\\*.* .\\\r
        cls\r
        @vbox\r
        goto quit\r
        :MT32\r
        CONFIG -set "mididevice=mt32"\r
        copy .\\mt32\\*.* .\\\r
        cls\r
        @vbox\r
        goto quit\r
        :quit\r
        exit
        """

    @Test func readsEachOptionsTitleAndCommands() {
        let options = BatchMenuReader.options(in: boxing)
        #expect(options.map(\.title) == ["ABC Wide World of Sports Boxing w/ SoundBlaster",
                                         "ABC Wide World of Sports Boxing w/ MT-32"])
        #expect(options[1].commands == ["CONFIG -set \"mididevice=mt32\"", "copy .\\mt32\\*.* .\\", "vbox"])
    }

    @Test func followsFolderChangesAndCallsBatchFiles() {
        let caves = """
            echo Press 1 for Crystal Caves Vol 1\r
            echo Press 2 for Crystal Caves Vol 2\r
            echo Press 4 to Quit\r
            choice /c:1234 /N Please Choose\r
            if errorlevel = 4 goto quit\r
            if errorlevel = 2 goto cc2\r
            if errorlevel = 1 goto cc1\r
            :cc1\r
            cls\r
            @cd cc1\r
            cc1\r
            cd ..\r
            goto menu\r
            :cc2\r
            @cd cc2\r
            cc2\r
            goto menu
            """
        let options = BatchMenuReader.options(in: caves) { folder, name in
            folder == ["cc2"] && name.lowercased() == "cc2"   // CC2 is a batch file in cc2
        }
        #expect(options.count == 2)
        #expect(options[0].commands == ["cd cc1", "cc1", "cd .."])
        #expect(options[1].commands == ["cd cc2", "CALL cc2"])
    }

    /// Each campaign starts with its own disc in, and "goto menu" after
    /// the game isn't followed back into the menu (Command & Conquer).
    @Test func keepsEachOptionsFirstDiscAndStopsAtTheMenu() {
        let script = """
        :menu
        echo Press 1 for GDI Campaign
        echo Press 2 for NOD Campaign
        echo Press 3 to Quit
        choice /C:123 /N Please Choose:
        if errorlevel = 3 goto quit
        if errorlevel = 2 goto NOD
        if errorlevel = 1 goto GDI
        :GDI
        imgmount d ".\\eXoDOS\\comcon\\cd\\CD-1.iso" ".\\eXoDOS\\comcon\\cd\\CD-2.iso" -t cdrom
        @C&C
        goto menu
        :NOD
        imgmount d ".\\eXoDOS\\comcon\\cd\\CD-2.iso" ".\\eXoDOS\\comcon\\cd\\CD-1.iso" -t cdrom
        @C&C
        goto menu
        :quit
        exit
        """
        let options = BatchMenuReader.options(in: script)
        #expect(options.map(\.commands) == [["C&C"], ["C&C"]])
        #expect(options.map(\.disc) == ["CD-1.iso", "CD-2.iso"])
    }

    @Test func ignoresScriptsThatArentMenus() {
        #expect(BatchMenuReader.options(in: "@echo off\r\ncd game\r\ngame.exe").isEmpty)
    }

    /// A two-step menu (like Blood's): pick a sound card, then which game.
    @Test func followsATwoStepMenu() throws {
        let script = """
        :menu
        echo Press 1 for Game w/ SoundBlaster
        echo Press 2 for Game w/ CD Audio
        choice /C:12 /N Please Choose:
        if errorlevel = 2 goto CDA
        if errorlevel = 1 goto SB16
        :SB16
        copy .\\game\\sb16\\*.* .\\game\\
        goto menu2
        :CDA
        imgmount d ".\\collection\\game\\cd\\game.cue" -t cdrom
        copy .\\game\\CDA\\*.* .\\game\\
        goto menu2
        :menu2
        echo Press 1 for Game
        echo Press 2 for Game: Expansion
        echo Press 3 to launch Setup
        choice /C:123 /N Please Choose:
        if errorlevel = 3 goto setup
        if errorlevel = 2 goto expansion
        if errorlevel = 1 goto game
        :game
        cd game
        game
        goto quit
        :expansion
        cd expansion
        game
        goto quit
        :setup
        cd game
        setup
        goto quit
        :quit
        exit
        """
        let options = BatchMenuReader.options(in: script)
        let cd = try #require(options.first { $0.title == "Game w/ CD Audio" })
        #expect(cd.commands == ["copy .\\game\\CDA\\*.* .\\game\\", "cd game", "game"])
        #expect(options.contains { $0.title == "Game: Expansion" })
        #expect(options.first?.title == "Game w/ SoundBlaster")
    }
}
