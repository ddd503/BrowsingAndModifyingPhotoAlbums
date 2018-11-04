/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implements the main view controller for album navigation.
*/

import UIKit
import Photos

// MARK - アルバム一覧画面
class MasterViewController: UITableViewController {
    
    // MARK: セクション、セル、およびセグの識別子を管理するための型
    enum Section: Int {
        case allPhotos = 0
        case smartAlbums
        case userCollections
        
        static let count = 3
    }
    
    enum CellIdentifier: String {
        case allPhotos, collection
    }
    
    enum SegueIdentifier: String {
        case showAllPhotos
        case showCollection
    }
    
    // MARK: Properties
    var allPhotos: PHFetchResult<PHAsset>!
    var smartAlbums: PHFetchResult<PHAssetCollection>!
    var userCollections: PHFetchResult<PHCollection>!
    let sectionLocalizedTitles = ["", NSLocalizedString("Smart Albums", comment: ""), NSLocalizedString("Albums", comment: "")]
    
    // MARK: UIViewController / Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(self.addAlbum))
        self.navigationItem.rightBarButtonItem = addButton
        
        // テーブルビューの各セクションのPHFetchResultオブジェクトを作成します。
        // fetch条件を指定
        let allPhotosOptions = PHFetchOptions()
        allPhotosOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        // ローカルからのfetch結果を受け取る（写真・動画の配列を取得）
        allPhotos = PHAsset.fetchAssets(with: allPhotosOptions)
        // ローカルからのfetch結果を受け取る（スマートアルバム(デフォルトアルバム)の配列を取得）
        smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .albumRegular, options: nil)
        // ローカルからのfetch結果を受け取る（PHAssetCollectionとPHCollectionListの抽象クラスの配列を取得）
        userCollections = PHCollectionList.fetchTopLevelUserCollections(with: nil)
        
        PHPhotoLibrary.shared().register(self)
    }
    
    /// - Tag: UnregisterChangeObserver
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        self.clearsSelectionOnViewWillAppear = self.splitViewController!.isCollapsed
        super.viewWillAppear(animated)
    }
    
    /// - Tag: CreateAlbum
    @objc
    func addAlbum(_ sender: AnyObject) {
        let alertController = UIAlertController(title: NSLocalizedString("New Album", comment: ""), message: nil, preferredStyle: .alert)
        alertController.addTextField { textField in
            textField.placeholder = NSLocalizedString("Album Name", comment: "")
        }
        
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Create", comment: ""), style: .default) { action in
            let textField = alertController.textFields!.first!
            if let title = textField.text, !title.isEmpty {
                // 入力したタイトルで新しいアルバムを作成します。
                PHPhotoLibrary.shared().performChanges({
                    PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                }, completionHandler: { success, error in
                    if !success { print("Error creating album: \(String(describing: error)).") }
                })
            }
        })
        self.present(alertController, animated: true, completion: nil)
    }
    
    // MARK: Segues
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        guard let destination = (segue.destination as? UINavigationController)?.topViewController as? AssetGridViewController
            else { fatalError("Unexpected view controller for segue.") }
        guard let cell = sender as? UITableViewCell else { fatalError("Unexpected sender for segue.") }
        
        destination.title = cell.textLabel?.text
        
        switch SegueIdentifier(rawValue: segue.identifier!)! {
        case .showAllPhotos:
            destination.fetchResult = allPhotos
        case .showCollection:
            
            // 選択した行のアセットコレクションを取得します。
            let indexPath = tableView.indexPath(for: cell)!
            let collection: PHCollection
            switch Section(rawValue: indexPath.section)! {
            case .smartAlbums:
                collection = smartAlbums.object(at: indexPath.row)
            case .userCollections:
                collection = userCollections.object(at: indexPath.row)
            default: return // デフォルトは、他のセグエーが既に写真セクションを処理したことを示します。
            }
            
            // アセットコレクションでビューコントローラを設定する
            guard let assetCollection = collection as? PHAssetCollection
                else { fatalError("Expected an asset collection.") }
            destination.fetchResult = PHAsset.fetchAssets(in: assetCollection, options: nil)
            destination.assetCollection = assetCollection
        }
    }
    
    // MARK: Table View
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .allPhotos: return 1
        case .smartAlbums: return smartAlbums.count
        case .userCollections: return userCollections.count
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .allPhotos:
            let cell = tableView.dequeueReusableCell(withIdentifier: CellIdentifier.allPhotos.rawValue, for: indexPath)
            cell.textLabel!.text = NSLocalizedString("All Photos", comment: "")
            return cell
            
        case .smartAlbums:
            let cell = tableView.dequeueReusableCell(withIdentifier: CellIdentifier.collection.rawValue, for: indexPath)
            let collection = smartAlbums.object(at: indexPath.row)
            cell.textLabel!.text = collection.localizedTitle
            return cell
            
        case .userCollections:
            let cell = tableView.dequeueReusableCell(withIdentifier: CellIdentifier.collection.rawValue, for: indexPath)
            let collection = userCollections.object(at: indexPath.row)
            cell.textLabel!.text = collection.localizedTitle
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sectionLocalizedTitles[section]
    }
    
}

// MARK: PHPhotoLibraryChangeObserver

extension MasterViewController: PHPhotoLibraryChangeObserver {
    /// - Tag: RespondToChanges
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        
        //通知の変更は、バックグラウンドキューから発生する可能性があります。
        //変更を実行する前にメインキューに再ディスパッチし、
        // UIを更新できるようにします。
        DispatchQueue.main.sync {
            // 3つのfetch配列(プロパティ)のそれぞれについて変更をチェックしてください。
            if let changeDetails = changeInstance.changeDetails(for: allPhotos) {
                // キャッシュされたフェッチ結果を更新します。
                allPhotos = changeDetails.fetchResultAfterChanges
                // Don't update the table row that always reads "All Photos." 全てを更新せずキャッシュ使え
            }
            
            // キャッシュされたフェッチ結果を更新し、一致するようにテーブルセクションをリロードします。
            if let changeDetails = changeInstance.changeDetails(for: smartAlbums) {
                smartAlbums = changeDetails.fetchResultAfterChanges
                tableView.reloadSections(IndexSet(integer: Section.smartAlbums.rawValue), with: .automatic)
            }
            if let changeDetails = changeInstance.changeDetails(for: userCollections) {
                userCollections = changeDetails.fetchResultAfterChanges
                tableView.reloadSections(IndexSet(integer: Section.userCollections.rawValue), with: .automatic)
            }
        }
    }
}

