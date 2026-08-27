import MapKit
import SwiftUI

/// One pin on the album map: a place, and the photos taken there.
///
/// A class conforming to `MKAnnotation` rather than a SwiftUI `Annotation`, because the pins have
/// to *cluster*. SwiftUI's `Map` draws whatever it is given and lets pins overlap; `MKMapView`
/// merges them by distance in pixels through `clusteringIdentifier` and hands the members back on
/// selection, which is exactly what the web map relies on.
final class PhotoPlaceAnnotation: NSObject, MKAnnotation {
    /// `@objc dynamic` because `MKMapView` observes it; a plain stored property would leave the
    /// pin where it was first drawn.
    @objc dynamic var coordinate: CLLocationCoordinate2D

    /// Also `@objc`: `MKAnnotation.title` is an optional Objective-C requirement, and Swift does
    /// not expose members of an `NSObject` subclass to the runtime on its own any more. Without
    /// it the property compiles, satisfies nothing, and the pin's callout comes up blank.
    @objc dynamic var title: String?

    let photoIDs: [Int]

    init(place: PhotoPlace) {
        coordinate = place.coordinate
        title = PhotoMapPlaces.title(forPhotoCount: place.photos.count)
        photoIDs = place.photos.map(\.id)
    }
}

/// The album's photos as pins on Apple Maps.
///
/// A port of the web app's `PhotoMap.vue` onto native MapKit. Two differences are worth knowing.
/// The web has to fetch a token from `/api/maps/token` before MapKit JS will draw anything, which
/// is why `/api/capabilities` advertises `maps.enabled` and why the web hides the filter without
/// it — native MapKit needs neither, so the map is offered here whenever the album has a located
/// photo. And where the web measures the page to size its canvas, a view here fills what it is
/// given.
struct PhotoMap: UIViewRepresentable {
    let places: [PhotoPlace]

    /// The framing to open at, or nil to fit every pin.
    let savedView: SavedMapView?

    /// The photos of the pin — or cluster of pins — just selected. Called with an empty list when
    /// the selection is dropped.
    let onSelect: ([Int]) -> Void

    /// The framing the map has settled on, after every pan, pinch and animation.
    ///
    /// This is how the owner's "Save this view" gets at a value SwiftUI otherwise cannot see. It
    /// is not a shadow copy of the region maintained by hand — it is `MKMapView` pushing its own
    /// `region` out once it has stopped moving, which is the same value the web reads off
    /// `map.region` at the moment of saving.
    var onRegionChanged: (SavedMapView) -> Void = { _ in }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: Coordinator.pinReuseID,
        )
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: Coordinator.clusterReuseID,
        )
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.onRegionChanged = onRegionChanged
        context.coordinator.sync(places: places, savedView: savedView, on: mapView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onRegionChanged: onRegionChanged)
    }

    /// Owns the pins and the delegate callbacks.
    ///
    /// `updateUIView` runs on every SwiftUI body pass, so this has to tell "the same album again"
    /// from "different photos": rebuilding the annotations either way would drop whatever pin the
    /// user had open, mid-look, and re-applying the framing would yank the map back while they
    /// were panning it.
    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        static let pinReuseID = "photo-place"
        static let clusterReuseID = "photo-place-cluster"

        var onSelect: ([Int]) -> Void
        var onRegionChanged: (SavedMapView) -> Void

        /// The place ids currently drawn, in order.
        private var drawnPlaceIDs: [String] = []

        private var hasAppliedView = false
        private var appliedView: SavedMapView?

        init(
            onSelect: @escaping ([Int]) -> Void,
            onRegionChanged: @escaping (SavedMapView) -> Void,
        ) {
            self.onSelect = onSelect
            self.onRegionChanged = onRegionChanged
        }

        func sync(places: [PhotoPlace], savedView: SavedMapView?, on mapView: MKMapView) {
            let ids = places.map(\.id)

            if ids != drawnPlaceIDs {
                mapView.removeAnnotations(mapView.annotations)
                mapView.addAnnotations(places.map(PhotoPlaceAnnotation.init(place:)))
                drawnPlaceIDs = ids
                // New pins mean the old framing was a guess about a different set of them.
                hasAppliedView = false
            }

            if !hasAppliedView || appliedView != savedView {
                apply(savedView, on: mapView)
                appliedView = savedView
                hasAppliedView = true
            }
        }

        /// Opens at the owner's framing when there is one, and fits every pin when there is not.
        ///
        /// Auto-fit is the better default — an album can span one park or three continents and
        /// both should open readable — but it is only ever a guess at what the album is *about*.
        /// A trip whose photos are all in Toronto except three from the airport layover fits to
        /// include the layover and opens showing mostly water. A saved view is the owner
        /// overriding that guess, so it wins outright rather than being merged with the bounds.
        private func apply(_ savedView: SavedMapView?, on mapView: MKMapView) {
            guard let savedView else {
                guard !mapView.annotations.isEmpty else { return }
                mapView.showAnnotations(mapView.annotations, animated: false)
                return
            }

            mapView.setRegion(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: savedView.centerLat,
                        longitude: savedView.centerLng,
                    ),
                    span: MKCoordinateSpan(
                        latitudeDelta: savedView.spanLat,
                        longitudeDelta: savedView.spanLng,
                    ),
                ),
                animated: false,
            )
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated _: Bool) {
            onRegionChanged(currentView(of: mapView))
        }

        /// The framing currently on screen, for the owner's "Save this view".
        ///
        /// Read off the live map rather than tracked as pans happen: `MKMapView` already maintains
        /// `region` through drags, pinches and its own `showAnnotations` animation, and a shadow
        /// copy would only be a chance to disagree with what the owner is looking at.
        private func currentView(of mapView: MKMapView) -> SavedMapView {
            let region = mapView.region
            return SavedMapView(
                centerLat: region.center.latitude,
                centerLng: region.center.longitude,
                spanLat: region.span.latitudeDelta,
                spanLng: region.span.longitudeDelta,
            )
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: Self.clusterReuseID,
                    for: cluster,
                ) as? MKMarkerAnnotationView
                view?.glyphText = PhotoMapPlaces.glyph(forPhotoCount: photoCount(in: cluster))
                view?.titleVisibility = .adaptive
                return view
            }

            guard let place = annotation as? PhotoPlaceAnnotation else { return nil }

            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: Self.pinReuseID,
                for: place,
            ) as? MKMarkerAnnotationView
            // Every pin shares the identifier because they are all the same kind of thing; this
            // is what makes MapKit merge the ones that overlap at the current zoom.
            view?.clusteringIdentifier = "photos"
            view?.glyphText = PhotoMapPlaces.glyph(forPhotoCount: place.photoIDs.count)
            view?.titleVisibility = .adaptive
            return view
        }

        func mapView(_: MKMapView, didSelect annotation: any MKAnnotation) {
            // A cluster carries its members; a plain pin is its own single member.
            if let cluster = annotation as? MKClusterAnnotation {
                onSelect(cluster.memberAnnotations.flatMap(photoIDs(of:)))
                return
            }
            onSelect(photoIDs(of: annotation))
        }

        func mapView(_: MKMapView, didDeselect _: any MKAnnotation) {
            onSelect([])
        }

        private func photoIDs(of annotation: any MKAnnotation) -> [Int] {
            (annotation as? PhotoPlaceAnnotation)?.photoIDs ?? []
        }

        private func photoCount(in cluster: MKClusterAnnotation) -> Int {
            cluster.memberAnnotations.reduce(0) { $0 + photoIDs(of: $1).count }
        }
    }
}
