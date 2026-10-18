// Mock del lettore MPRIS (media.cpp): una coda finta di brani
pragma Singleton
import QtQuick

QtObject {
    property bool available: true
    property string player: "Spotify"
    property bool playing: true
    property int track: 0
    readonly property var tracks: [["Dolomiti", "Arc Ensemble"], ["Rosa al tramonto", "Catinaccio"], ["Nebbia bassa", "Val di Fassa"]]
    readonly property string title: tracks[track][0]
    readonly property string artist: tracks[track][1]
    readonly property string artUrl: ""
    readonly property bool canGoNext: true
    readonly property bool canGoPrevious: true

    function playPause() { playing = !playing; }
    function next() { track = (track + 1) % tracks.length; }
    function previous() { track = (track + tracks.length - 1) % tracks.length; }
}
