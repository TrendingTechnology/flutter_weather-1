import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_weather/bloc/bloc.dart';
import 'package:flutter_weather/localization.dart';
import 'package:flutter_weather/model.dart';
import 'package:flutter_weather/theme.dart';
import 'package:flutter_weather/utils/color_utils.dart';
import 'package:flutter_weather/views/forecast/forecast_utils.dart';
import 'package:flutter_weather/views/forecast/widgets/forecast_display.dart';
import 'package:flutter_weather/views/forecast/widgets/forecast_options.dart';
import 'package:flutter_weather/views/lookup/lookup_view.dart';
import 'package:flutter_weather/widgets/app_none_found.dart';
import 'package:flutter_weather/widgets/app_pageview_scroll_physics.dart';
import 'package:flutter_weather/widgets/app_ui_overlay_style.dart';
import 'package:page_view_indicators/circle_page_indicator.dart';

class ForecastView extends StatelessWidget {
  static Route route() =>
      MaterialPageRoute<void>(builder: (_) => ForecastView());

  const ForecastView({
    Key key,
  }) : super(key: key);

  @override
  Widget build(
    BuildContext context,
  ) =>
      ForecastPageView();
}

class ForecastPageView extends StatefulWidget {
  ForecastPageView({
    Key key,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ForecastPageViewState();
}

class _ForecastPageViewState extends State<ForecastPageView>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();

  PageController _pageController;
  Animatable<Color> _pageBackground;
  ValueNotifier<int> _currentForecastNotifier;
  double _currentPage = 0.0;

  @override
  void initState() {
    super.initState();

    AppState state = context.read<AppBloc>().state;

    _pageController = PageController(initialPage: state.selectedForecastIndex)
      ..addListener(() => _currentPage = _pageController.page);

    if (state.colorTheme) {
      _pageBackground = buildForecastColorSequence(state.forecasts);
    }

    _currentForecastNotifier = ValueNotifier<int>(state.selectedForecastIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) =>
      Scaffold(
        key: _scaffoldKey,
        extendBody: true,
        body: BlocListener<AppBloc, AppState>(
          listener: _blocListener,
          child: WillPopScope(
            onWillPop: () => _willPopCallback(context.read<AppBloc>().state),
            child: _buildBody(context.watch<AppBloc>().state),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: AppLocalizations.of(context).addForecast,
          onPressed: _tapAddLocation,
          child: Icon(Icons.add),
          mini: true,
        ),
      );

  void _blocListener(
    BuildContext context,
    AppState state,
  ) {
    if (state.crudStatus != null) {
      AppLocalizations i18n = AppLocalizations.of(context);

      switch (state.crudStatus) {
        case CRUDStatus.CREATED:
          _scaffoldKey.currentState
              .showSnackBar(SnackBar(content: Text(i18n.forecastAdded)));
          break;

        case CRUDStatus.UPDATED:
          _scaffoldKey.currentState
              .showSnackBar(SnackBar(content: Text(i18n.forecastUpdated)));
          break;

        case CRUDStatus.DELETED:
          _scaffoldKey.currentState
              .showSnackBar(SnackBar(content: Text(i18n.forecastDeleted)));
          break;

        default:
          break;
      }

      context.read<AppBloc>().add(ClearCRUDStatus());
    }

    if (state.colorTheme) {
      _pageBackground = buildForecastColorSequence(state.forecasts);
    }
  }

  Future<bool> _willPopCallback(
    AppState state,
  ) async {
    if (state.selectedForecastIndex == 0) {
      // Exits the app
      SystemChannels.platform.invokeMethod('SystemNavigator.pop');
    } else {
      // Go back to the first forecast
      _pageController.jumpToPage(0);
      context.read<AppBloc>().add(SelectedForecastIndex(0));
    }

    return Future.value(false);
  }

  Widget _buildBody(
    AppState state,
  ) =>
      state.colorTheme
          ? _buildForecastColorContent(state)
          : _buildLightDarkContent(state);

  Widget _buildContent(
    AppState state,
  ) =>
      Column(
        children: <Widget>[
          ForecastOptions(),
          Expanded(
            child: state.forecasts.isEmpty
                ? AppNoneFound(text: AppLocalizations.of(context).noForecasts)
                : PageView.builder(
                    controller: _pageController,
                    physics: AppPageViewScrollPhysics(),
                    itemCount: state.forecasts.length,
                    itemBuilder: (BuildContext context, int position) =>
                        _buildForecastItem(context, position, state),
                    onPageChanged: _onPageChanged,
                  ),
          ),
          _buildCircleIndicator(state),
        ],
      );

  Widget _buildForecastColorContent(
    AppState state,
  ) =>
      AnimatedBuilder(
        animation: _pageController,
        builder: (BuildContext context, Widget child) {
          final double _forecastColorValue = _pageController.hasClients &&
                  (state.forecasts != null) &&
                  state.forecasts.isNotEmpty
              ? (_currentPage / state.forecasts.length)
              : 0.0;

          Color _forecastColor = _pageBackground.evaluate(
            AlwaysStoppedAnimation(_forecastColorValue),
          );

          Color _forecastDarkenedColor = _forecastColor.darken(0.25);

          return AppUiOverlayStyle(
            themeMode: state.themeMode,
            colorTheme: state.colorTheme,
            systemNavigationBarColor: _forecastDarkenedColor,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _forecastColor,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _forecastColor,
                    _forecastDarkenedColor,
                  ],
                ),
              ),
              child: SafeArea(child: _buildContent(state)),
            ),
          );
        },
      );

  _buildLightDarkContent(
    AppState state,
  ) =>
      AppUiOverlayStyle(
        themeMode: state.themeMode,
        colorTheme: state.colorTheme,
        child: SafeArea(child: _buildContent(state)),
      );

  _buildForecastItem(
    BuildContext context,
    int position,
    AppState state,
  ) {
    if (position == state.forecasts.length) {
      return null;
    }

    if (canRefresh(state)) {
      return RefreshIndicator(
        color: AppTheme.primaryColor,
        onRefresh: () => _pullRefresh(state),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ForecastDisplay(
            bloc: context.read<AppBloc>(),
            forecast: state.forecasts[position],
          ),
        ),
      );
    }

    return ForecastDisplay(
      bloc: context.read<AppBloc>(),
      forecast: state.forecasts[position],
    );
  }

  _buildCircleIndicator(
    AppState state,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 20.0),
        child: CirclePageIndicator(
          dotColor: AppTheme.getHintColor(
            state.themeMode,
          ),
          selectedDotColor:
              state.colorTheme ? Colors.white : AppTheme.primaryColor,
          selectedSize: 10.0,
          itemCount: (state.forecasts == null) ? 0 : state.forecasts.length,
          currentPageNotifier: _currentForecastNotifier,
          onPageSelected: _onPageChanged,
        ),
      );

  void _onPageChanged(
    int page,
  ) {
    context.read<AppBloc>().add(SelectedForecastIndex(page));
    _currentForecastNotifier.value = page;
  }

  Future<void> _pullRefresh(
    AppState state,
  ) async =>
      context.read<AppBloc>().add(RefreshForecast(
            state.forecasts[state.selectedForecastIndex],
            state.temperatureUnit,
          ));

  void _tapAddLocation() => Navigator.push(context, LookupView.route());
}
