//
//  StationsViewController.swift
//  Swift Radio
//
//  Created by Matthew Fecher on 7/19/15.
//  Copyright (c) 2015 MatthewFecher.com. All rights reserved.
//

import UIKit
import MediaPlayer
import AVFoundation

class StationsViewController: UIViewController {
    
    // MARK: - IB UI


    @IBOutlet weak var stationNowPlayingButton: UIButton!
    @IBOutlet weak var nowPlayingAnimationImageView: UIImageView!
    
    @IBAction func GoToRadio(_ sender: Any) {
        let currentStation = stations[0]
        radioPlayer.station = currentStation
        performSegue(withIdentifier: "NowPlaying", sender: nil)
    }
    // MARK: - Properties
    
    let radioPlayer = RadioPlayer()
    
    // Weak reference to update the NowPlayingViewController
    weak var nowPlayingViewController: NowPlayingViewController?
    
    // MARK: - Lists
    
    var stations = [RadioStation]() {
        didSet {
            guard stations != oldValue else { return }
            stationsDidUpdate()
        }
    }
    
    var searchedStations = [RadioStation]()
    
    // MARK: - UI
    
    var searchController: UISearchController = {
        return UISearchController(searchResultsController: nil)
    }()
    
    var refreshControl: UIRefreshControl = {
        return UIRefreshControl()
    }()
    
    //*****************************************************************
    // MARK: - ViewDidLoad
    //*****************************************************************
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Register 'Nothing Found' cell xib

        
        // Setup Player :: Required in experimental app
        radioPlayer.delegate = self
        
        // Load Data
        loadStationsFromJSON()
        
        // Setup TableView


        
        // Create NowPlaying Animation
        createNowPlayingAnimation()
        
        // Activate audioSession
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            if kDebugLog { print("audioSession could not be activated") }
        }
        
        // Setup Search Bar

        
        // Setup Remote Command Center
        setupRemoteCommandCenter()
        
        // Setup Handoff User Activity
        setupHandoffUserActivity()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        title = "Swift Radio"
    }

    //*****************************************************************
    // MARK: - Setup UI Elements
    //*****************************************************************
    

    
    func createNowPlayingAnimation() {
        nowPlayingAnimationImageView.animationImages = AnimationFrames.createFrames()
        nowPlayingAnimationImageView.animationDuration = 0.7
    }
    
    func createNowPlayingBarButton() {
        guard navigationItem.rightBarButtonItem == nil else { return }
        let btn = UIBarButtonItem(title: "", style: .plain, target: self, action:#selector(nowPlayingBarButtonPressed))
        btn.image = UIImage(named: "btn-nowPlaying")
        navigationItem.rightBarButtonItem = btn
    }
    
    //*****************************************************************
    // MARK: - Actions
    //*****************************************************************
    
    @objc func nowPlayingBarButtonPressed() {
        performSegue(withIdentifier: "NowPlaying", sender: self)
    }
    
    @IBAction func nowPlayingPressed(_ sender: UIButton) {
        performSegue(withIdentifier: "NowPlaying", sender: self)
    }
    
    @objc func refresh(sender: AnyObject) {
        // Pull to Refresh
        loadStationsFromJSON()
        
        // Wait 2 seconds then refresh screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.refreshControl.endRefreshing()
            self.view.setNeedsDisplay()
        }
    }
    
    //*****************************************************************
    // MARK: - Load Station Data
    //*****************************************************************
    
    func loadStationsFromJSON() {
        
        // Turn on network indicator in status bar
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        
        // Get the Radio Stations
        DataManager.getStationDataWithSuccess() { (data) in
            
            // Turn off network indicator in status bar
            defer {
                DispatchQueue.main.async { UIApplication.shared.isNetworkActivityIndicatorVisible = false }
            }
            
            if kDebugLog { print("Stations JSON Found") }
            
            guard let data = data, let jsonDictionary = try? JSONDecoder().decode([String: [RadioStation]].self, from: data), let stationsArray = jsonDictionary["station"] else {
                if kDebugLog { print("JSON Station Loading Error") }
                return
            }
            
            self.stations = stationsArray
        }
    }
    
    //*****************************************************************
    // MARK: - Segue
    //*****************************************************************
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard segue.identifier == "NowPlaying", let nowPlayingVC = segue.destination as? NowPlayingViewController else { return }
        
        title = ""
        
        let newStation: Bool
        
        if let indexPath = (sender as? IndexPath) {
            // User clicked on row, load/reset station
            radioPlayer.station = stations[indexPath.row]
            newStation = true
        } else {
            // User clicked on Now Playing button
            newStation = true
        }
        
        nowPlayingViewController = nowPlayingVC
        nowPlayingVC.load(station: radioPlayer.station, track: radioPlayer.track, isNewStation: newStation)
        nowPlayingVC.delegate = self
    }
    
    //*****************************************************************
    // MARK: - Private helpers
    //*****************************************************************
    
    private func stationsDidUpdate() {
        DispatchQueue.main.async {
            guard let currentStation = self.radioPlayer.station else { return }
            
            // Reset everything if the new stations list doesn't have the current station
            if self.stations.index(of: currentStation) == nil { self.resetCurrentStation() }
        }
    }
    
    // Reset all properties to default
    private func resetCurrentStation() {
        radioPlayer.resetRadioPlayer()
        nowPlayingAnimationImageView.stopAnimating()
        stationNowPlayingButton.setTitle("Choose a station above to begin", for: .normal)
        stationNowPlayingButton.isEnabled = false
        navigationItem.rightBarButtonItem = nil
    }
    
    // Update the now playing button title
    private func updateNowPlayingButton(station: RadioStation?, track: Track?) {
        guard let station = station else { resetCurrentStation(); return }
        
        var playingTitle = station.name + ": "
        
        if track?.title == station.name {
            playingTitle += "Now playing ..."
        } else if let track = track {
            playingTitle += track.title + " - " + track.artist
        }
        
        stationNowPlayingButton.setTitle(playingTitle, for: .normal)
        stationNowPlayingButton.isEnabled = true
        createNowPlayingBarButton()
    }
    
    func startNowPlayingAnimation(_ animate: Bool) {
        animate ? nowPlayingAnimationImageView.startAnimating() : nowPlayingAnimationImageView.stopAnimating()
    }
    
    private func getIndex(of station: RadioStation?) -> Int? {
        guard let station = station, let index = stations.index(of: station) else { return nil }
        return index
    }
    
    //*****************************************************************
    // MARK: - Remote Command Center Controls
    //*****************************************************************
    
    func setupRemoteCommandCenter() {
        // Get the shared MPRemoteCommandCenter
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Add handler for Play Command
        commandCenter.playCommand.addTarget { event in
            return .success
        }
        
        // Add handler for Pause Command
        commandCenter.pauseCommand.addTarget { event in
            return .success
        }
        
        // Add handler for Next Command
        commandCenter.nextTrackCommand.addTarget { event in
            return .success
        }
        
        // Add handler for Previous Command
        commandCenter.previousTrackCommand.addTarget { event in
            return .success
        }
    }
    
    //*****************************************************************
    // MARK: - MPNowPlayingInfoCenter (Lock screen)
    //*****************************************************************
    
    func updateLockScreen(with track: Track?) {
        
        // Define Now Playing Info
        var nowPlayingInfo = [String : Any]()
        
        if let image = track?.artworkImage {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(image: image)
        }
        
        if let artist = track?.artist {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }
        
        if let title = track?.title {
            nowPlayingInfo[MPMediaItemPropertyTitle] = title
        }
        
        // Set the metadata
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}

//*****************************************************************
// MARK: - TableViewDataSource
//*****************************************************************



//*****************************************************************
// MARK: - TableViewDelegate
//*****************************************************************



//*****************************************************************
// MARK: - UISearchControllerDelegate / Setup
//*****************************************************************



//*****************************************************************
// MARK: - RadioPlayerDelegate
//*****************************************************************

extension StationsViewController: RadioPlayerDelegate {
    
    func playerStateDidChange(_ playerState: FRadioPlayerState) {
        nowPlayingViewController?.playerStateDidChange(playerState, animate: true)
    }
    
    func playbackStateDidChange(_ playbackState: FRadioPlaybackState) {
        nowPlayingViewController?.playbackStateDidChange(playbackState, animate: true)
        startNowPlayingAnimation(radioPlayer.player.isPlaying)
    }
    
    func trackDidUpdate(_ track: Track?) {
        updateLockScreen(with: track)
        updateNowPlayingButton(station: radioPlayer.station, track: track)
        updateHandoffUserActivity(userActivity, station: radioPlayer.station, track: track)
        nowPlayingViewController?.updateTrackMetadata(with: track)
    }
    
    func trackArtworkDidUpdate(_ track: Track?) {
        updateLockScreen(with: track)
        nowPlayingViewController?.updateTrackArtwork(with: track)
    }
}

//*****************************************************************
// MARK: - Handoff Functionality - GH
//*****************************************************************

extension StationsViewController {
    
    func setupHandoffUserActivity() {
        userActivity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        userActivity?.becomeCurrent()
    }
    
    func updateHandoffUserActivity(_ activity: NSUserActivity?, station: RadioStation?, track: Track?) {
        guard let activity = activity else { return }
        activity.webpageURL = (track?.title == station?.name) ? nil : getHandoffURL(from: track)
        updateUserActivityState(activity)
    }
    
    override func updateUserActivityState(_ activity: NSUserActivity) {
        super.updateUserActivityState(activity)
    }
    
    private func getHandoffURL(from track: Track?) -> URL? {
        guard let track = track else { return nil }
        
        var components = URLComponents()
        components.scheme = "https"
        components.host = "google.com"
        components.path = "/search"
        components.queryItems = [URLQueryItem]()
        components.queryItems?.append(URLQueryItem(name: "q", value: "\(track.artist) \(track.title)"))
        return components.url
    }
}

//*****************************************************************
// MARK: - NowPlayingViewControllerDelegate
//*****************************************************************

extension StationsViewController: NowPlayingViewControllerDelegate {
    
    func didPressPlayingButton() {
        radioPlayer.player.togglePlaying()
    }
    
    func didPressStopButton() {
        radioPlayer.player.stop()
    }
    
    func didPressNextButton() {
        guard let index = getIndex(of: radioPlayer.station) else { return }
        radioPlayer.station = (index + 1 == stations.count) ? stations[0] : stations[index + 1]
        handleRemoteStationChange()
    }
    
    func didPressPreviousButton() {
        guard let index = getIndex(of: radioPlayer.station) else { return }
        radioPlayer.station = (index == 0) ? stations.last : stations[index - 1]
        handleRemoteStationChange()
    }
    
    private func handleRemoteStationChange() {
        if let nowPlayingVC = nowPlayingViewController {
            // If nowPlayingVC is presented
            nowPlayingVC.load(station: radioPlayer.station, track: radioPlayer.track)
            nowPlayingVC.stationDidChange()
        } else if let station = radioPlayer.station {
            // If nowPlayingVC is not presented (change from remote controls)
            radioPlayer.player.radioURL = URL(string: station.streamURL)
        }
    }
}
